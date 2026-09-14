create or replace function public.notify_order_status_change()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_store uuid;
  v_customer_body text;
  v_courier_body text;
  v_merchant_body text;
begin
  if new.status_code is not distinct from old.status_code then
    return new;
  end if;

  v_customer_body := case new.status_code
    when 'paid' then 'Pagamento confirmado. A loja já recebeu seu pedido.'
    when 'preparing' then 'A loja está preparando seu pedido.'
    when 'ready' then case
      when new.delivery_method='pickup' then 'Seu pedido está pronto para retirada na loja.'
      else 'Seu pedido está pronto e aguardando a próxima etapa da entrega.'
    end
    when 'awaiting_courier' then 'Estamos procurando um entregador para seu pedido.'
    when 'courier_assigned' then 'Um entregador aceitou a entrega e está indo até a loja.'
    when 'picked_up' then 'O entregador retirou seu pedido na loja.'
    when 'out_for_delivery' then 'Seu pedido saiu para entrega.'
    when 'delivered' then 'Pedido entregue com sucesso.'
    when 'cancel_requested' then 'Sua solicitação de cancelamento foi registrada.'
    when 'cancelled' then 'Seu pedido foi cancelado.'
    when 'returning' then 'A devolução do seu pedido está em andamento.'
    when 'returned' then 'A devolução do seu pedido foi concluída.'
    else 'O status do seu pedido foi atualizado.'
  end;

  v_courier_body := case new.status_code
    when 'courier_assigned' then 'Entrega aceita. Siga até a loja para realizar a coleta.'
    when 'picked_up' then 'Coleta confirmada. Inicie a entrega ao cliente.'
    when 'out_for_delivery' then 'Entrega iniciada. Siga até o endereço do cliente.'
    when 'delivered' then 'Entrega concluída com sucesso.'
    when 'cancelled' then 'Esta entrega foi cancelada.'
    else 'O status da entrega foi atualizado.'
  end;

  v_merchant_body := case new.status_code
    when 'paid' then 'Novo pedido pago. Inicie a preparação.'
    when 'preparing' then 'Pedido marcado como em preparação.'
    when 'ready' then case
      when new.delivery_method='pickup' then 'Pedido pronto para retirada pelo cliente.'
      when new.delivery_method='store_delivery' then 'Pedido pronto para entrega pela loja.'
      else 'Pedido pronto. Solicite um entregador parceiro.'
    end
    when 'awaiting_courier' then 'Pedido oferecido aos entregadores parceiros.'
    when 'courier_assigned' then 'Um entregador aceitou e está indo até a loja.'
    when 'picked_up' then 'O entregador retirou o pedido na loja.'
    when 'out_for_delivery' then case
      when new.delivery_method='store_delivery' then 'A entrega da loja foi iniciada.'
      else 'O entregador iniciou a entrega ao cliente.'
    end
    when 'delivered' then 'Pedido entregue. Os lançamentos financeiros foram gerados.'
    when 'cancel_requested' then 'O cliente solicitou o cancelamento deste pedido.'
    when 'cancelled' then 'Este pedido foi cancelado.'
    when 'returning' then 'A devolução deste pedido está em andamento.'
    when 'returned' then 'A devolução deste pedido foi concluída.'
    else 'O status do pedido foi atualizado.'
  end;

  insert into public.notifications(user_id,channel,type,title,body,data,status)
  values(
    new.user_id,
    'in_app',
    'order_status',
    'Atualização do pedido',
    v_customer_body,
    jsonb_build_object('order_id',new.id,'status',new.status_code,'recipient','customer'),
    'pending'
  );

  if new.courier_user_id is not null
     and new.status_code in ('courier_assigned','picked_up','out_for_delivery','delivered','cancelled') then
    insert into public.notifications(user_id,channel,type,title,body,data,status)
    values(
      new.courier_user_id,
      'in_app',
      'delivery_status',
      'Atualização da entrega',
      v_courier_body,
      jsonb_build_object('order_id',new.id,'status',new.status_code,'recipient','courier'),
      'pending'
    );
  end if;

  select oi.store_id
    into v_store
  from public.order_items oi
  where oi.order_id=new.id
  limit 1;

  if v_store is not null then
    insert into public.notifications(user_id,channel,type,title,body,data,status)
    select
      sm.user_id,
      'in_app',
      'merchant_order',
      'Pedido atualizado',
      v_merchant_body,
      jsonb_build_object('order_id',new.id,'status',new.status_code,'recipient','merchant'),
      'pending'
    from public.store_members sm
    where sm.store_id=v_store;
  end if;

  return new;
end
$function$;
