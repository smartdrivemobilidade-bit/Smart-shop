-- Garante que o cliente e a loja recebam a confirmação inicial do pedido.
-- As demais etapas continuam sendo notificadas por notify_order_status_change().
create or replace function public.notify_new_paid_order()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_store uuid;
  v_order_label text;
begin
  if new.status_code <> 'paid' then
    return new;
  end if;

  v_order_label := coalesce(nullif(new.order_number, ''), left(new.id::text, 8));

  insert into public.notifications(user_id, channel, type, title, body, data, status)
  values (
    new.user_id,
    'in_app',
    'order_status',
    'Pedido confirmado',
    format('Pedido %s confirmado. O pagamento foi aprovado e a loja já recebeu seu pedido.', v_order_label),
    jsonb_build_object(
      'order_id', new.id,
      'order_number', new.order_number,
      'status', new.status_code,
      'recipient', 'customer'
    ),
    'pending'
  );

  select oi.store_id
    into v_store
  from public.order_items oi
  where oi.order_id = new.id
  limit 1;

  if v_store is not null then
    insert into public.notifications(user_id, channel, type, title, body, data, status)
    select
      sm.user_id,
      'in_app',
      'new_order',
      'Novo pedido recebido',
      format('Pedido %s pago. Inicie a preparação.', v_order_label),
      jsonb_build_object(
        'order_id', new.id,
        'order_number', new.order_number,
        'status', new.status_code,
        'recipient', 'merchant'
      ),
      'pending'
    from public.store_members sm
    where sm.store_id = v_store;
  end if;

  return new;
end
$function$;

revoke all on function public.notify_new_paid_order() from public, anon, authenticated;

