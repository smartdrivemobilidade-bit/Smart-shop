-- Frete do parceiro Smart Shop calculado pela distância estimada entre loja e cliente.

alter table public.addresses
  add column if not exists latitude numeric check (latitude between -90 and 90),
  add column if not exists longitude numeric check (longitude between -180 and 180);

create table if not exists public.delivery_city_coordinates (
  city text not null,
  state text not null,
  latitude numeric not null check (latitude between -90 and 90),
  longitude numeric not null check (longitude between -180 and 180),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (city, state)
);

alter table public.delivery_city_coordinates enable row level security;
revoke all on table public.delivery_city_coordinates from anon, authenticated;
grant select on table public.delivery_city_coordinates to anon, authenticated;
grant insert, update, delete on table public.delivery_city_coordinates to authenticated;

drop policy if exists "delivery city coordinates public read" on public.delivery_city_coordinates;
drop policy if exists "delivery city coordinates admin manage" on public.delivery_city_coordinates;
create policy "delivery city coordinates public read"
  on public.delivery_city_coordinates for select
  to anon, authenticated
  using (active = true);
create policy "delivery city coordinates admin manage"
  on public.delivery_city_coordinates for all
  to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

insert into public.delivery_city_coordinates(city, state, latitude, longitude)
values
  ('Mateus Leme', 'MG', -19.9817, -44.4278),
  ('Itaúna', 'MG', -20.0750, -44.5760),
  ('Juatuba', 'MG', -19.9510, -44.3420),
  ('Betim', 'MG', -19.9678, -44.1983),
  ('Florestal', 'MG', -19.8880, -44.4310),
  ('Contagem', 'MG', -19.9320, -44.0530),
  ('Pará de Minas', 'MG', -19.8600, -44.6080),
  ('Esmeraldas', 'MG', -19.7620, -44.3130)
on conflict (city, state) do nothing;

insert into public.platform_settings(key, value, updated_at)
values
  ('smart_partner_base_freight', '8'::jsonb, now()),
  ('smart_partner_per_km', '0.75'::jsonb, now()),
  ('smart_partner_min_freight', '12'::jsonb, now()),
  ('smart_partner_max_freight', '60'::jsonb, now()),
  ('smart_partner_max_distance_km', '40'::jsonb, now())
on conflict (key) do nothing;

create or replace function public.get_checkout_settings()
returns jsonb
language sql
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'smart_partner_freight', coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_freight'), 12),
    'store_delivery_freight', coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='store_delivery_freight'), 8),
    'smart_partner_base_freight', coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_base_freight'), 8),
    'smart_partner_per_km', coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_per_km'), 0.75),
    'smart_partner_min_freight', coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_min_freight'), 12),
    'smart_partner_max_freight', coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_max_freight'), 60),
    'smart_partner_max_distance_km', coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_max_distance_km'), 40)
  );
$function$;

revoke all on function public.get_checkout_settings() from public, anon;
grant execute on function public.get_checkout_settings() to authenticated;

create or replace function public.set_platform_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_num numeric;
begin
  if not public.is_platform_admin() then
    raise exception 'not authorized';
  end if;

  if p_key in ('merchant_commission_rate', 'freight_commission_rate') then
    if jsonb_typeof(p_value) <> 'number' then
      raise exception 'invalid commission rate';
    end if;
    v_num := (p_value #>> '{}')::numeric;
    if v_num < 0 or v_num > 1 then
      raise exception 'invalid commission rate';
    end if;
  elsif p_key in (
    'smart_partner_freight', 'store_delivery_freight',
    'smart_partner_base_freight', 'smart_partner_per_km',
    'smart_partner_min_freight', 'smart_partner_max_freight',
    'smart_partner_max_distance_km'
  ) then
    if jsonb_typeof(p_value) <> 'number' then
      raise exception 'invalid freight';
    end if;
    v_num := (p_value #>> '{}')::numeric;
    if v_num < 0 or v_num > 10000 then
      raise exception 'invalid freight';
    end if;
    if p_key = 'smart_partner_max_distance_km' and v_num > 200 then
      raise exception 'invalid maximum delivery distance';
    end if;
  else
    raise exception 'setting not allowed';
  end if;

  insert into public.platform_settings(key, value, updated_at, updated_by)
  values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update
  set value = excluded.value, updated_at = now(), updated_by = auth.uid();

  insert into public.audit_logs(actor_user_id, actor_role, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'admin', 'update_setting', 'platform_setting', p_key,
          jsonb_build_object('value', p_value));
end;
$function$;

revoke all on function public.set_platform_setting(text, jsonb) from public, anon;
grant execute on function public.set_platform_setting(text, jsonb) to authenticated;

create or replace function public.quote_checkout_distance(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid,
  p_delivery_method text,
  p_coupon_code text default null
)
returns table(
  product_subtotal numeric,
  discount_amount numeric,
  freight_amount numeric,
  total_amount numeric,
  coupon_code text,
  distance_km numeric,
  pricing_note text
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_addr public.addresses%rowtype;
  v_store public.stores%rowtype;
  v_quote record;
  v_store_lat numeric;
  v_store_lng numeric;
  v_addr_lat numeric;
  v_addr_lng numeric;
  v_haversine_a numeric;
  v_distance_km numeric;
  v_base numeric := 8;
  v_per_km numeric := 0.75;
  v_min_freight numeric := 12;
  v_max_freight numeric := 60;
  v_max_distance_km numeric := 40;
  v_legacy_freight numeric := 12;
  v_freight numeric := 0;
  v_note text := null;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  select * into v_addr
  from public.addresses
  where id = p_address_id and user_id = v_uid;
  if not found then
    raise exception 'invalid address';
  end if;

  select * into v_store
  from public.stores
  where id = p_store_id and active = true and approval_status = 'approved';
  if not found then
    raise exception 'store unavailable';
  end if;

  select q.* into v_quote
  from public.quote_checkout(p_store_id, p_items, p_delivery_method, p_coupon_code) q;

  select
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_base_freight'), 8),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_per_km'), 0.75),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_min_freight'), 12),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_max_freight'), 60),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_max_distance_km'), 40),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_freight'), 12)
  into v_base, v_per_km, v_min_freight, v_max_freight, v_max_distance_km, v_legacy_freight;

  if p_delivery_method = 'pickup' then
    v_freight := 0;
    v_note := 'Retirada na loja';
  elsif p_delivery_method = 'store_delivery' then
    select coalesce(store_delivery_fee, 8) into v_freight
    from public.stores where id = p_store_id;
    v_note := 'Valor definido pela loja';
  elsif p_delivery_method = 'smart_partner' then
    select
      coalesce(v_store.latitude, (select c.latitude from public.delivery_city_coordinates c where lower(trim(c.city))=lower(trim(v_store.city)) and upper(trim(c.state))=upper(trim(v_store.state)) and c.active=true limit 1)),
      coalesce(v_store.longitude, (select c.longitude from public.delivery_city_coordinates c where lower(trim(c.city))=lower(trim(v_store.city)) and upper(trim(c.state))=upper(trim(v_store.state)) and c.active=true limit 1))
    into v_store_lat, v_store_lng;

    select
      coalesce(v_addr.latitude, (select c.latitude from public.delivery_city_coordinates c where lower(trim(c.city))=lower(trim(v_addr.city)) and upper(trim(c.state))=upper(trim(v_addr.state)) and c.active=true limit 1)),
      coalesce(v_addr.longitude, (select c.longitude from public.delivery_city_coordinates c where lower(trim(c.city))=lower(trim(v_addr.city)) and upper(trim(c.state))=upper(trim(v_addr.state)) and c.active=true limit 1))
    into v_addr_lat, v_addr_lng;

    if v_store_lat is null or v_store_lng is null or v_addr_lat is null or v_addr_lng is null then
      if lower(trim(v_store.city)) = lower(trim(v_addr.city)) and upper(trim(v_store.state)) = upper(trim(v_addr.state)) then
        v_freight := v_legacy_freight;
        v_note := 'Frete local; distância estimada pendente';
      else
        raise exception 'delivery distance unavailable';
      end if;
    else
      v_haversine_a :=
        power(sin(radians((v_addr_lat-v_store_lat)/2)),2) +
        cos(radians(v_store_lat))*cos(radians(v_addr_lat))*
        power(sin(radians((v_addr_lng-v_store_lng)/2)),2);
      v_distance_km := round((greatest(0, 6371 * 2 * asin(sqrt(least(1, greatest(0, v_haversine_a))))) * 1.25)::numeric, 1);
      if v_distance_km > v_max_distance_km then
        raise exception 'delivery distance exceeds coverage';
      end if;
      v_max_freight := greatest(v_max_freight, v_min_freight);
      v_freight := round(greatest(v_min_freight, least(v_max_freight, v_base + v_per_km * v_distance_km)), 2);
      v_note := format('Distância estimada: %s km', replace(to_char(v_distance_km, 'FM999990.0'), '.', ','));
    end if;
  else
    raise exception 'invalid delivery method';
  end if;

  return query
  select v_quote.product_subtotal,
         v_quote.discount_amount,
         v_freight,
         v_quote.product_subtotal-v_quote.discount_amount+v_freight,
         v_quote.coupon_code,
         v_distance_km,
         v_note;
end;
$function$;

revoke all on function public.quote_checkout_distance(uuid, jsonb, uuid, text, text) from public, anon;
grant execute on function public.quote_checkout_distance(uuid, jsonb, uuid, text, text) to authenticated;

create or replace function public.create_checkout_order_distance(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid,
  p_delivery_method text,
  p_coupon_code text default null,
  p_checkout_token text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_order uuid;
  v_existing uuid;
  v_profile public.profiles%rowtype;
  v_addr public.addresses%rowtype;
  v_item jsonb;
  v_product public.products%rowtype;
  v_variant public.product_variants%rowtype;
  v_variant_id uuid;
  v_variant_label text;
  v_qty int;
  v_sub numeric := 0;
  v_freight numeric := 0;
  v_discount numeric := 0;
  v_coupon public.coupons%rowtype;
  v_uses int := 0;
  v_coupon_base numeric := 0;
  v_quote record;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  if nullif(p_checkout_token, '') is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_uid::text || ':' || p_checkout_token, 0));
    select id into v_existing
    from public.orders
    where user_id = v_uid and checkout_token = p_checkout_token
    limit 1;
    if v_existing is not null then
      return v_existing;
    end if;
  end if;

  select * into v_addr from public.addresses where id=p_address_id and user_id=v_uid;
  if not found then raise exception 'invalid address'; end if;
  select * into v_profile from public.profiles where id=v_uid;

  select q.* into v_quote
  from public.quote_checkout_distance(p_store_id,p_items,p_address_id,p_delivery_method,p_coupon_code) q;
  v_freight := coalesce(v_quote.freight_amount, 0);
  v_discount := coalesce(v_quote.discount_amount, 0);

  for v_item in select * from jsonb_array_elements(p_items) loop
    begin
      v_qty := (v_item->>'quantity')::int;
    exception when others then
      raise exception 'invalid quantity';
    end;
    if v_qty < 1 then raise exception 'invalid quantity'; end if;

    select * into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid and store_id=p_store_id and active=true
    for update;
    if not found then raise exception 'product unavailable'; end if;
    if v_product.stock < v_qty then raise exception 'insufficient stock for %', v_product.name; end if;

    if exists(select 1 from public.product_variants where product_id=v_product.id and active=true) then
      if nullif(v_item->>'variant_id','') is null then raise exception 'variant required'; end if;
      select * into v_variant
      from public.product_variants
      where id=(v_item->>'variant_id')::uuid and product_id=v_product.id and store_id=p_store_id and active=true
      for update;
      if not found then raise exception 'variant unavailable'; end if;
      if v_variant.stock < v_qty then raise exception 'insufficient variant stock'; end if;
    end if;
    v_sub := v_sub + (v_product.price * v_qty);
  end loop;

  if nullif(trim(coalesce(p_coupon_code,'')), '') is not null then
    select * into v_coupon
    from public.coupons
    where upper(code)=upper(trim(p_coupon_code)) and active=true
      and (starts_at is null or starts_at<=now())
      and (expires_at is null or expires_at>=now())
    for update;
    if not found then raise exception 'invalid coupon'; end if;
    if v_coupon.scope_type='store' and v_coupon.store_id is distinct from p_store_id then raise exception 'coupon not valid for this store'; end if;
    if v_coupon.scope_type='category' then
      select coalesce(sum(p.price*((j->>'quantity')::int)),0) into v_coupon_base
      from jsonb_array_elements(p_items) j
      join public.products p on p.id=(j->>'product_id')::uuid
      where p.store_id=p_store_id and p.category=v_coupon.category;
      if v_coupon_base<=0 then raise exception 'coupon not valid for cart category'; end if;
    else
      v_coupon_base := v_sub;
    end if;
    if v_coupon_base < v_coupon.min_order_amount then raise exception 'coupon minimum not reached'; end if;
    select count(*) into v_uses from public.coupon_redemptions where coupon_id=v_coupon.id and user_id=v_uid;
    if v_uses >= v_coupon.per_user_limit then raise exception 'coupon already used'; end if;
    if v_coupon.usage_limit is not null and (select count(*) from public.coupon_redemptions where coupon_id=v_coupon.id) >= v_coupon.usage_limit then raise exception 'coupon usage limit reached'; end if;
    v_discount := case when v_coupon.discount_type='percent' then round(v_coupon_base*v_coupon.discount_value/100,2) else least(v_coupon.discount_value,v_coupon_base) end;
  end if;

  insert into public.orders(
    user_id,address_id,customer_name,customer_phone,delivery_street,delivery_number,
    delivery_district,delivery_complement,delivery_cep,delivery_city,delivery_state,
    total_amount,status_code,delivery_method,freight_amount,checkout_token,
    product_subtotal,discount_amount
  )
  values(
    v_uid,v_addr.id,coalesce(v_profile.full_name,'Cliente Smart Shop'),v_profile.phone,
    v_addr.street,v_addr.number,v_addr.district,v_addr.complement,v_addr.cep,
    v_addr.city,v_addr.state,v_sub-v_discount+v_freight,'paid',p_delivery_method,
    v_freight,p_checkout_token,v_sub,v_discount
  ) returning id into v_order;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::int;
    v_variant_id := null;
    v_variant_label := null;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and store_id=p_store_id for update;
    if nullif(v_item->>'variant_id','') is not null then
      v_variant_id := (v_item->>'variant_id')::uuid;
      select * into v_variant from public.product_variants where id=v_variant_id and product_id=v_product.id and store_id=p_store_id and active=true for update;
      if not found then raise exception 'variant unavailable'; end if;
      v_variant_label := concat_ws(' • ', nullif(v_variant.color,''), nullif(v_variant.size,''));
      update public.product_variants set stock=stock-v_qty, updated_at=now() where id=v_variant.id;
    end if;
    insert into public.order_items(order_id,product_id,store_id,product_name,quantity,unit_price,variant_id,variant_label,selected_options)
    values(v_order,v_product.id,p_store_id,v_product.name,v_qty,v_product.price,v_variant_id,v_variant_label,
           jsonb_strip_nulls(jsonb_build_object('color',case when v_variant_id is null then null else v_variant.color end,'size',case when v_variant_id is null then null else v_variant.size end,'sku',case when v_variant_id is null then null else v_variant.sku end)));
    update public.products set stock=stock-v_qty, updated_at=now() where id=v_product.id;
  end loop;

  if v_coupon.id is not null then
    insert into public.coupon_redemptions(coupon_id,user_id,order_id,discount_amount)
    values(v_coupon.id,v_uid,v_order,v_discount);
  end if;

  insert into public.order_status_history(order_id,status_code,label,actor_user_id,actor_type,notes)
  values(v_order,'paid','Pago / Confirmado',v_uid,'customer','Pedido criado pelo checkout');
  return v_order;
exception when unique_violation then
  if nullif(p_checkout_token, '') is not null then
    select id into v_existing from public.orders where user_id=v_uid and checkout_token=p_checkout_token;
    if v_existing is not null then return v_existing; end if;
  end if;
  raise;
end;
$function$;

revoke all on function public.create_checkout_order_distance(uuid, jsonb, uuid, text, text, text) from public, anon;
grant execute on function public.create_checkout_order_distance(uuid, jsonb, uuid, text, text, text) to authenticated;
