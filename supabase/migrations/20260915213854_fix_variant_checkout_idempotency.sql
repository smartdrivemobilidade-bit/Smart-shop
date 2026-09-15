create or replace function public.create_checkout_order_v2(
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
  v_item jsonb;
  v_product_id uuid;
  v_variant_id uuid;
  v_qty integer;
  v_variant public.product_variants%rowtype;
  v_label text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  -- Serializa tentativas com o mesmo token. Assim, clique duplo ou repeticao
  -- da requisicao devolve o pedido ja criado sem baixar o estoque novamente.
  if nullif(p_checkout_token, '') is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_uid::text || ':' || p_checkout_token, 0));

    select id into v_order
    from public.orders
    where user_id = v_uid and checkout_token = p_checkout_token
    limit 1;

    if v_order is not null then
      return v_order;
    end if;
  end if;

  perform * from public.quote_checkout_v2(p_store_id,p_items,p_delivery_method,p_coupon_code);
  v_order := public.create_checkout_order(p_store_id,p_items,p_address_id,p_delivery_method,p_coupon_code,p_checkout_token);

  if not exists(select 1 from public.orders where id=v_order and user_id=v_uid) then
    raise exception 'order ownership validation failed';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    if nullif(v_item->>'variant_id','') is not null then
      v_variant_id := (v_item->>'variant_id')::uuid;
      select * into v_variant from public.product_variants
      where id=v_variant_id and product_id=v_product_id and store_id=p_store_id and active=true
      for update;
      if not found then raise exception 'variant unavailable'; end if;
      if v_variant.stock < v_qty then raise exception 'insufficient variant stock'; end if;

      update public.product_variants set stock=stock-v_qty,updated_at=now() where id=v_variant.id;
      v_label := concat_ws(' • ', nullif(v_variant.color,''), nullif(v_variant.size,''));
      update public.order_items
      set variant_id=v_variant.id,
          variant_label=v_label,
          selected_options=jsonb_strip_nulls(jsonb_build_object('color',v_variant.color,'size',v_variant.size,'sku',v_variant.sku))
      where order_id=v_order and product_id=v_product_id;
    end if;
  end loop;

  return v_order;
end
$function$;

revoke all on function public.create_checkout_order_v2(uuid,jsonb,uuid,text,text,text) from public, anon;
grant execute on function public.create_checkout_order_v2(uuid,jsonb,uuid,text,text,text) to authenticated;
