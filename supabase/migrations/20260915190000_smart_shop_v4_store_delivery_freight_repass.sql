-- Na entrega própria, o frete pertence à loja, que remunera seu próprio entregador.
-- A comissão de produtos da plataforma permanece inalterada.
create or replace function public.settle_store_delivery_freight()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_store uuid;
  v_owner uuid;
  v_ledger_id uuid;
  v_freight numeric := greatest(coalesce(new.freight_amount, 0), 0);
begin
  if new.status_code <> 'delivered'
     or old.status_code is not distinct from 'delivered'
     or new.delivery_method <> 'store_delivery'
     or v_freight <= 0 then
    return new;
  end if;

  select oi.store_id
    into v_store
  from public.order_items oi
  where oi.order_id = new.id
  limit 1;

  select sm.user_id
    into v_owner
  from public.store_members sm
  where sm.store_id = v_store and sm.role = 'owner'
  order by sm.created_at
  limit 1;

  if v_owner is null then
    raise exception 'merchant owner not found for store delivery';
  end if;

  insert into public.financial_ledger
    (order_id, beneficiary_type, beneficiary_user_id, store_id, amount, entry_type, status, available_at, notes)
  values
    (new.id, 'merchant', v_owner, v_store, v_freight, 'freight_earning', 'available', now(),
     'Frete da entrega realizada pela própria loja')
  on conflict do nothing
  returning id into v_ledger_id;

  if v_ledger_id is not null then
    update public.orders
    set merchant_net_amount = coalesce(merchant_net_amount, 0) + v_freight,
        updated_at = now()
    where id = new.id;

    insert into public.audit_logs(actor_user_id, actor_role, action, entity_type, entity_id, metadata)
    values (
      auth.uid(),
      'system',
      'settle_store_delivery_freight',
      'order',
      new.id::text,
      jsonb_build_object('store_id', v_store, 'freight_amount', v_freight)
    );
  end if;

  return new;
end
$function$;

drop trigger if exists trg_settle_store_delivery_freight on public.orders;
create trigger trg_settle_store_delivery_freight
after update of status_code on public.orders
for each row execute function public.settle_store_delivery_freight();

revoke all on function public.settle_store_delivery_freight() from public, anon, authenticated;

