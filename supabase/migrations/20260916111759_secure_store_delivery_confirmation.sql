create or replace function public.confirm_store_delivery(p_order_id uuid, p_code text)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_expected text;
  v_store uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select oi.store_id into v_store
  from public.orders o
  join public.order_items oi on oi.order_id=o.id
  where o.id=p_order_id
    and o.delivery_method='store_delivery'
    and o.status_code='out_for_delivery'
  limit 1
  for update of o;

  if v_store is null or not public.is_store_member(v_store) then
    raise exception 'delivery not allowed';
  end if;

  perform public.ensure_order_verification_codes(p_order_id);
  select delivery_code into v_expected
  from public.order_verification_codes
  where order_id=p_order_id;

  if trim(coalesce(p_code,''))<>v_expected then
    raise exception 'invalid delivery code';
  end if;

  update public.orders set status_code='delivered',updated_at=now() where id=p_order_id;
  insert into public.order_status_history(order_id,status_code,label,actor_user_id,actor_type,notes)
  values(p_order_id,'delivered','Entrega da loja concluída',v_uid,'merchant','Código do cliente validado');
end
$function$;

revoke all on function public.confirm_store_delivery(uuid,text) from public,anon;
grant execute on function public.confirm_store_delivery(uuid,text) to authenticated;

create or replace function public.smart_order_transition(p_order_id uuid, p_new_status text, p_notes text default null)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare v_order public.orders%rowtype; v_actor uuid:=auth.uid(); v_actor_type text; v_ok boolean:=false; v_store uuid; v_is_merchant boolean:=false;
begin
 if v_actor is null then raise exception 'authentication required'; end if;
 select * into v_order from public.orders where id=p_order_id for update; if not found then raise exception 'order not found'; end if;
 select oi.store_id into v_store from public.order_items oi where oi.order_id=p_order_id limit 1;
 v_is_merchant:=exists(select 1 from public.store_members sm where sm.store_id=v_store and sm.user_id=v_actor);
 if p_new_status='cancel_requested' and v_order.user_id=v_actor then v_actor_type:='customer';
 elsif v_is_merchant and p_new_status in ('preparing','ready','awaiting_courier','out_for_delivery','delivered') then v_actor_type:='merchant';
 elsif v_order.courier_user_id=v_actor then v_actor_type:='courier';
 elsif v_order.user_id=v_actor then v_actor_type:='customer';
 elsif v_is_merchant then v_actor_type:='merchant';
 elsif public.is_platform_admin() then v_actor_type:='admin';
 else raise exception 'access denied'; end if;
 if v_actor_type='merchant' then
  v_ok:=(v_order.status_code='paid' and p_new_status='preparing')
    or (v_order.status_code='preparing' and p_new_status='ready')
    or (v_order.delivery_method='smart_partner' and v_order.status_code='ready' and p_new_status='awaiting_courier')
    or (v_order.delivery_method='store_delivery' and v_order.status_code='ready' and p_new_status='out_for_delivery')
    or (v_order.delivery_method='pickup' and v_order.status_code='ready' and p_new_status='delivered');
 elsif v_actor_type='customer' then v_ok:=(v_order.status_code in ('awaiting_payment','paid') and p_new_status='cancel_requested');
 elsif v_actor_type='admin' then v_ok:=p_new_status in ('paid','preparing','ready','awaiting_courier','courier_assigned','picked_up','out_for_delivery','delivered','cancelled','returning','returned');
 else v_ok:=false; end if;
 if not v_ok then raise exception 'invalid status transition % -> % for %',v_order.status_code,p_new_status,v_actor_type; end if;
 update public.orders set status_code=p_new_status,updated_at=now() where id=p_order_id;
 insert into public.order_status_history(order_id,status_code,label,actor_user_id,actor_type,notes)
 values(p_order_id,p_new_status,case when p_new_status='preparing' then 'Em preparação' when p_new_status='ready' then 'Pedido pronto' when p_new_status='awaiting_courier' then 'Procurando entregador' when p_new_status='out_for_delivery' and v_order.delivery_method='store_delivery' then 'Saiu para entrega pela loja' when p_new_status='delivered' and v_order.delivery_method='pickup' then 'Retirado pelo cliente' else replace(initcap(replace(p_new_status,'_',' ')),'Courier','Entregador') end,v_actor,v_actor_type,p_notes);
 if p_new_status='awaiting_courier' then insert into public.deliveries(order_id,store_id,status,freight_amount,offered_at) values(p_order_id,v_store,'waiting_courier',coalesce(v_order.freight_amount,0),now()) on conflict(order_id) do update set status='waiting_courier',courier_user_id=null,vehicle_id=null,offered_at=now(),updated_at=now(); end if;
end
$function$;

revoke all on function public.smart_order_transition(uuid,text,text) from public,anon;
grant execute on function public.smart_order_transition(uuid,text,text) to authenticated;
