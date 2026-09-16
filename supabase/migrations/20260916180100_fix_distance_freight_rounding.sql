-- Corrige a conversão numérica da fórmula de distância do frete.

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
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_addr from public.addresses where id=p_address_id and user_id=v_uid;
  if not found then raise exception 'invalid address'; end if;
  select * into v_store from public.stores where id=p_store_id and active=true and approval_status='approved';
  if not found then raise exception 'store unavailable'; end if;

  select q.* into v_quote from public.quote_checkout(p_store_id,p_items,p_delivery_method,p_coupon_code) q;
  select
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_base_freight'),8),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_per_km'),0.75),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_min_freight'),12),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_max_freight'),60),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_max_distance_km'),40),
    coalesce((select (value #>> '{}')::numeric from public.platform_settings where key='smart_partner_freight'),12)
  into v_base,v_per_km,v_min_freight,v_max_freight,v_max_distance_km,v_legacy_freight;

  if p_delivery_method='pickup' then
    v_freight:=0; v_note:='Retirada na loja';
  elsif p_delivery_method='store_delivery' then
    select coalesce(store_delivery_fee,8) into v_freight from public.stores where id=p_store_id;
    v_note:='Valor definido pela loja';
  elsif p_delivery_method='smart_partner' then
    select
      coalesce(v_store.latitude,(select c.latitude from public.delivery_city_coordinates c where lower(trim(c.city))=lower(trim(v_store.city)) and upper(trim(c.state))=upper(trim(v_store.state)) and c.active=true limit 1)),
      coalesce(v_store.longitude,(select c.longitude from public.delivery_city_coordinates c where lower(trim(c.city))=lower(trim(v_store.city)) and upper(trim(c.state))=upper(trim(v_store.state)) and c.active=true limit 1))
    into v_store_lat,v_store_lng;
    select
      coalesce(v_addr.latitude,(select c.latitude from public.delivery_city_coordinates c where lower(trim(c.city))=lower(trim(v_addr.city)) and upper(trim(c.state))=upper(trim(v_addr.state)) and c.active=true limit 1)),
      coalesce(v_addr.longitude,(select c.longitude from public.delivery_city_coordinates c where lower(trim(c.city))=lower(trim(v_addr.city)) and upper(trim(c.state))=upper(trim(v_addr.state)) and c.active=true limit 1))
    into v_addr_lat,v_addr_lng;

    if v_store_lat is null or v_store_lng is null or v_addr_lat is null or v_addr_lng is null then
      if lower(trim(v_store.city))=lower(trim(v_addr.city)) and upper(trim(v_store.state))=upper(trim(v_addr.state)) then
        v_freight:=v_legacy_freight; v_note:='Frete local; distância estimada pendente';
      else
        raise exception 'delivery distance unavailable';
      end if;
    else
      v_haversine_a:=power(sin(radians((v_addr_lat-v_store_lat)/2)),2)+cos(radians(v_store_lat))*cos(radians(v_addr_lat))*power(sin(radians((v_addr_lng-v_store_lng)/2)),2);
      v_distance_km:=round((greatest(0,6371*2*asin(sqrt(least(1,greatest(0,v_haversine_a)))))*1.25)::numeric,1);
      if v_distance_km>v_max_distance_km then raise exception 'delivery distance exceeds coverage'; end if;
      v_max_freight:=greatest(v_max_freight,v_min_freight);
      v_freight:=round(greatest(v_min_freight,least(v_max_freight,v_base+v_per_km*v_distance_km)),2);
      v_note:=format('Distância estimada: %s km',replace(to_char(v_distance_km,'FM999990.0'),'.',','));
    end if;
  else
    raise exception 'invalid delivery method';
  end if;

  return query select v_quote.product_subtotal,v_quote.discount_amount,v_freight,v_quote.product_subtotal-v_quote.discount_amount+v_freight,v_quote.coupon_code,v_distance_km,v_note;
end;
$function$;

revoke all on function public.quote_checkout_distance(uuid,jsonb,uuid,text,text) from public,anon;
grant execute on function public.quote_checkout_distance(uuid,jsonb,uuid,text,text) to authenticated;
