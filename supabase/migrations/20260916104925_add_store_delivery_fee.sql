alter table public.stores
  add column if not exists store_delivery_fee numeric(10,2) not null default 8.00;

alter table public.stores
  drop constraint if exists stores_store_delivery_fee_check;

alter table public.stores
  add constraint stores_store_delivery_fee_check check (store_delivery_fee >= 0);

drop function if exists public.update_my_store_settings(uuid,text,text,text,text,text,text,text,text,text[]);

create function public.update_my_store_settings(
  p_store_id uuid,
  p_name text,
  p_description text default null,
  p_category text default null,
  p_phone text default null,
  p_whatsapp text default null,
  p_email text default null,
  p_business_hours text default null,
  p_logo_url text default null,
  p_delivery_modes text[] default null,
  p_store_delivery_fee numeric default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_modes text[];
  v_fee numeric;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not public.is_store_member(p_store_id) and not public.is_platform_admin() then raise exception 'not authorized'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'store name required'; end if;

  v_modes := coalesce(p_delivery_modes,array['pickup','smart_partner']::text[]);
  if cardinality(v_modes)=0 or exists(select 1 from unnest(v_modes) m where m not in ('pickup','store_delivery','smart_partner')) then
    raise exception 'invalid delivery mode';
  end if;

  select store_delivery_fee into v_fee from public.stores where id=p_store_id;
  v_fee := coalesce(p_store_delivery_fee,v_fee,8.00);
  if v_fee < 0 then raise exception 'invalid store delivery fee'; end if;

  update public.stores
  set name=trim(p_name),description=nullif(trim(p_description),''),category=nullif(trim(p_category),''),
      phone=nullif(trim(p_phone),''),whatsapp=nullif(trim(p_whatsapp),''),email=nullif(trim(p_email),''),
      business_hours=nullif(trim(p_business_hours),''),logo_url=nullif(trim(p_logo_url),''),
      delivery_modes=v_modes,store_delivery_fee=round(v_fee,2),updated_at=now()
  where id=p_store_id;

  insert into public.audit_logs(actor_user_id,actor_role,action,entity_type,entity_id,metadata)
  values(v_uid,'merchant','update_store_settings','store',p_store_id::text,
         jsonb_build_object('name',trim(p_name),'delivery_modes',v_modes,'store_delivery_fee',round(v_fee,2)));
end
$function$;

revoke all on function public.update_my_store_settings(uuid,text,text,text,text,text,text,text,text,text[],numeric) from public,anon;
grant execute on function public.update_my_store_settings(uuid,text,text,text,text,text,text,text,text,text[],numeric) to authenticated;

create or replace function public.quote_checkout(p_store_id uuid, p_items jsonb, p_delivery_method text, p_coupon_code text default null)
returns table(product_subtotal numeric, discount_amount numeric, freight_amount numeric, total_amount numeric, coupon_code text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid:=auth.uid(); v_item jsonb; v_product public.products%rowtype; v_qty int;
  v_sub numeric:=0; v_freight numeric:=0; v_discount numeric:=0; v_coupon public.coupons%rowtype;
  v_uses int:=0; v_modes text[]; v_coupon_base numeric:=0; v_store_delivery_fee numeric:=8;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_delivery_method not in ('pickup','store_delivery','smart_partner') then raise exception 'invalid delivery method'; end if;
  select delivery_modes,store_delivery_fee into v_modes,v_store_delivery_fee from public.stores where id=p_store_id and active=true and approval_status='approved';
  if not found then raise exception 'store unavailable'; end if;
  if not (p_delivery_method=any(coalesce(v_modes,array[]::text[]))) then raise exception 'delivery method unavailable for this store'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'empty cart'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    begin v_qty:=(v_item->>'quantity')::int; exception when others then raise exception 'invalid quantity'; end;
    if v_qty<1 then raise exception 'invalid quantity'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and store_id=p_store_id and active=true;
    if not found then raise exception 'product unavailable'; end if;
    if v_product.stock<v_qty then raise exception 'insufficient stock for %',v_product.name; end if;
    v_sub:=v_sub+(v_product.price*v_qty);
  end loop;
  if p_delivery_method='smart_partner' then
    select coalesce((value#>>'{}')::numeric,12) into v_freight from public.platform_settings where key='smart_partner_freight';
    v_freight:=coalesce(v_freight,12);
  elsif p_delivery_method='store_delivery' then
    v_freight:=coalesce(v_store_delivery_fee,8);
  end if;
  if nullif(trim(coalesce(p_coupon_code,'')),'') is not null then
    select * into v_coupon from public.coupons where upper(code)=upper(trim(p_coupon_code)) and active=true and (starts_at is null or starts_at<=now()) and (expires_at is null or expires_at>=now());
    if not found then raise exception 'invalid coupon'; end if;
    if v_coupon.scope_type='store' and v_coupon.store_id is distinct from p_store_id then raise exception 'coupon not valid for this store'; end if;
    if v_coupon.scope_type='category' then
      select coalesce(sum(p.price*((j->>'quantity')::int)),0) into v_coupon_base from jsonb_array_elements(p_items) j join public.products p on p.id=(j->>'product_id')::uuid where p.store_id=p_store_id and p.category=v_coupon.category;
      if v_coupon_base<=0 then raise exception 'coupon not valid for cart category'; end if;
    else v_coupon_base:=v_sub; end if;
    if v_coupon_base<v_coupon.min_order_amount then raise exception 'coupon minimum not reached'; end if;
    select count(*) into v_uses from public.coupon_redemptions where coupon_id=v_coupon.id and user_id=v_uid;
    if v_uses>=v_coupon.per_user_limit then raise exception 'coupon already used'; end if;
    if v_coupon.usage_limit is not null and (select count(*) from public.coupon_redemptions where coupon_id=v_coupon.id)>=v_coupon.usage_limit then raise exception 'coupon usage limit reached'; end if;
    v_discount:=case when v_coupon.discount_type='percent' then round(v_coupon_base*v_coupon.discount_value/100,2) else least(v_coupon.discount_value,v_coupon_base) end;
  end if;
  return query select v_sub,v_discount,v_freight,v_sub-v_discount+v_freight,case when v_coupon.id is null then null else v_coupon.code end;
end
$function$;

revoke all on function public.quote_checkout(uuid,jsonb,text,text) from public,anon;
grant execute on function public.quote_checkout(uuid,jsonb,text,text) to authenticated;
