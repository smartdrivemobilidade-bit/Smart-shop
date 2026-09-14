create or replace function public.record_delivery_location_event(
  p_delivery_id uuid,
  p_event_type text,
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_m numeric default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_delivery public.deliveries%rowtype;
  v_store public.stores%rowtype;
  v_order public.orders%rowtype;
  v_target_lat numeric;
  v_target_lng numeric;
  v_target_type text;
  v_radius numeric := 200;
  v_distance numeric;
  v_valid boolean;
  v_id uuid;
  v_notes text;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if p_event_type not in ('arrived_store','pickup','arrived_customer','delivered') then
    raise exception 'invalid location event type';
  end if;
  if p_latitude is null or p_latitude < -90 or p_latitude > 90
     or p_longitude is null or p_longitude < -180 or p_longitude > 180 then
    raise exception 'invalid coordinates';
  end if;
  if p_accuracy_m is null or p_accuracy_m <= 0 or p_accuracy_m > 150 then
    raise exception 'Localização imprecisa. Aguarde o GPS melhorar para continuar.';
  end if;

  select * into v_delivery
  from public.deliveries
  where id=p_delivery_id and courier_user_id=auth.uid()
  for update;
  if not found then
    raise exception 'Entrega não pertence ao entregador autenticado';
  end if;

  if p_event_type='arrived_store' and v_delivery.status<>'accepted' then
    raise exception 'A chegada à loja não está disponível nesta etapa';
  elsif p_event_type='pickup' and v_delivery.status<>'arrived_store' then
    raise exception 'A coleta não está disponível nesta etapa';
  elsif p_event_type in ('arrived_customer','delivered') and v_delivery.status<>'out_for_delivery' then
    raise exception 'A confirmação no destino não está disponível nesta etapa';
  end if;

  select * into v_order from public.orders where id=v_delivery.order_id;
  select * into v_store from public.stores where id=v_delivery.store_id;

  if p_event_type in ('arrived_store','pickup') then
    v_target_type := 'store';
    v_target_lat := v_store.latitude;
    v_target_lng := v_store.longitude;
  else
    v_target_type := 'customer';
    v_target_lat := v_order.delivery_latitude;
    v_target_lng := v_order.delivery_longitude;
  end if;

  if v_target_lat is not null and v_target_lng is not null then
    v_distance := 6371000 * 2 * asin(sqrt(
      power(sin(radians((p_latitude-v_target_lat)/2)),2) +
      cos(radians(v_target_lat))*cos(radians(p_latitude))*
      power(sin(radians((p_longitude-v_target_lng)/2)),2)
    ));
    v_valid := v_distance <= v_radius;
    v_notes := p_notes;
  else
    v_distance := null;
    v_valid := null;
    v_notes := concat_ws(' | ',nullif(trim(coalesce(p_notes,'')),''),'Exceção automática: destino sem coordenadas cadastradas');
  end if;

  insert into public.delivery_location_events(
    delivery_id,courier_user_id,event_type,latitude,longitude,accuracy_m,
    target_type,distance_to_target_m,geofence_radius_m,geofence_valid,notes
  )
  values(
    p_delivery_id,auth.uid(),p_event_type,p_latitude,p_longitude,p_accuracy_m,
    v_target_type,v_distance,v_radius,v_valid,v_notes
  )
  returning id into v_id;

  return v_id;
end
$function$;

create or replace function public.courier_arrived_store(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_delivery_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select d.id into v_delivery_id
  from public.orders o
  join public.deliveries d on d.order_id=o.id
  where o.id=p_order_id
    and o.courier_user_id=v_uid
    and o.status_code='courier_assigned'
    and d.courier_user_id=v_uid
    and d.status='accepted'
  for update of d;

  if v_delivery_id is null then raise exception 'order unavailable'; end if;

  if not exists(
    select 1 from public.delivery_location_events e
    where e.delivery_id=v_delivery_id
      and e.courier_user_id=v_uid
      and e.event_type='arrived_store'
      and e.created_at>=now()-interval '15 minutes'
      and e.geofence_valid is distinct from false
  ) then
    raise exception 'Registre uma localização válida na loja para continuar';
  end if;

  update public.deliveries set status='arrived_store',updated_at=now()
  where id=v_delivery_id;

  insert into public.order_status_history(order_id,status_code,label,actor_user_id,actor_type,notes)
  values(p_order_id,'courier_assigned','Entregador chegou à loja',v_uid,'courier','GPS/geofence validado');
end
$function$;

create or replace function public.confirm_order_pickup(p_order_id uuid,p_code text)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_expected text;
  v_delivery_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select d.id into v_delivery_id
  from public.orders o
  join public.deliveries d on d.order_id=o.id
  where o.id=p_order_id
    and o.courier_user_id=v_uid
    and o.status_code='courier_assigned'
    and d.courier_user_id=v_uid
    and d.status='arrived_store'
  for update of d;

  if v_delivery_id is null then raise exception 'pickup not allowed'; end if;

  if not exists(
    select 1 from public.delivery_location_events e
    where e.delivery_id=v_delivery_id
      and e.courier_user_id=v_uid
      and e.event_type='pickup'
      and e.created_at>=now()-interval '15 minutes'
      and e.geofence_valid is distinct from false
  ) then
    raise exception 'Registre uma localização válida para confirmar a coleta';
  end if;

  perform public.ensure_order_verification_codes(p_order_id);
  select pickup_code into v_expected
  from public.order_verification_codes
  where order_id=p_order_id;

  if trim(coalesce(p_code,''))<>v_expected then
    raise exception 'invalid pickup code';
  end if;

  update public.orders set status_code='picked_up',updated_at=now() where id=p_order_id;
  update public.deliveries set status='picked_up',picked_up_at=now(),updated_at=now() where id=v_delivery_id;

  insert into public.order_status_history(order_id,status_code,label,actor_user_id,actor_type,notes)
  values(p_order_id,'picked_up','Pedido retirado na loja',v_uid,'courier','GPS/geofence validado');
end
$function$;

create or replace function public.confirm_order_delivery(p_order_id uuid,p_code text)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_expected text;
  v_delivery_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select d.id into v_delivery_id
  from public.orders o
  join public.deliveries d on d.order_id=o.id
  where o.id=p_order_id
    and o.courier_user_id=v_uid
    and o.status_code='out_for_delivery'
    and d.courier_user_id=v_uid
    and d.status='out_for_delivery'
  for update of d;

  if v_delivery_id is null then raise exception 'delivery not allowed'; end if;

  if not exists(
    select 1 from public.delivery_location_events e
    where e.delivery_id=v_delivery_id
      and e.courier_user_id=v_uid
      and e.event_type='delivered'
      and e.created_at>=now()-interval '15 minutes'
      and e.geofence_valid is distinct from false
  ) then
    raise exception 'Registre uma localização válida no destino para confirmar a entrega';
  end if;

  perform public.ensure_order_verification_codes(p_order_id);
  select delivery_code into v_expected
  from public.order_verification_codes
  where order_id=p_order_id;

  if trim(coalesce(p_code,''))<>v_expected then
    raise exception 'invalid delivery code';
  end if;

  update public.orders set status_code='delivered',updated_at=now() where id=p_order_id;
  update public.deliveries set status='delivered',delivered_at=now(),updated_at=now() where id=v_delivery_id;

  insert into public.order_status_history(order_id,status_code,label,actor_user_id,actor_type,notes)
  values(p_order_id,'delivered','Entrega concluída',v_uid,'courier','GPS/geofence validado');
end
$function$;