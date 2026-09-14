create or replace function public.settle_delivered_order()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_products numeric:=0;
  v_discount numeric:=0;
  v_rate numeric:=0.10;
  v_commission numeric:=0;
  v_merchant_net numeric:=0;
  v_platform_net numeric:=0;
  v_platform_subsidy numeric:=0;
  v_store uuid;
  v_store_count int:=0;
  v_owner uuid;
  v_funding text:='platform';
begin
  if new.status_code='delivered' and old.status_code is distinct from 'delivered' then
    select coalesce(sum(oi.subtotal),0),count(distinct oi.store_id)
      into v_products,v_store_count
    from public.order_items oi
    where oi.order_id=new.id;

    select oi.store_id
      into v_store
    from public.order_items oi
    where oi.order_id=new.id
    limit 1;

    if v_store_count<>1 then
      raise exception 'delivered order must contain exactly one store';
    end if;

    v_discount:=greatest(coalesce(new.discount_amount,0),0);
    if new.coupon_id is not null then
      select coalesce(funding_source,'platform')
        into v_funding
      from public.coupons
      where id=new.coupon_id;
    end if;

    begin
      select coalesce((value#>>'{}')::numeric,0.10)
        into v_rate
      from public.platform_settings
      where key='merchant_commission_rate';
    exception when others then
      v_rate:=0.10;
    end;

    v_rate:=greatest(0,least(1,v_rate));
    v_commission:=round(v_products*v_rate,2);

    if v_funding='store' then
      v_merchant_net:=greatest(round(v_products-v_commission-v_discount,2),0);
      v_platform_net:=v_commission;
      v_platform_subsidy:=0;
    else
      v_merchant_net:=round(v_products-v_commission,2);
      v_platform_net:=greatest(round(v_commission-v_discount,2),0);
      v_platform_subsidy:=v_discount;
    end if;

    update public.orders
    set product_subtotal=v_products,
        commission_amount=v_commission,
        merchant_net_amount=v_merchant_net,
        platform_subsidy_amount=v_platform_subsidy,
        platform_net_revenue=v_platform_net,
        total_amount=case when total_amount=0 then greatest(v_products-v_discount,0)+coalesce(freight_amount,0) else total_amount end,
        updated_at=now()
    where id=new.id;

    select sm.user_id
      into v_owner
    from public.store_members sm
    where sm.store_id=v_store and sm.role='owner'
    order by sm.created_at
    limit 1;

    if v_owner is null then
      raise exception 'merchant owner not found for delivered order';
    end if;

    insert into public.financial_ledger(order_id,beneficiary_type,beneficiary_user_id,store_id,amount,entry_type,status,available_at,notes)
    values(new.id,'merchant',v_owner,v_store,greatest(v_merchant_net,0),'sale_net','available',now(),case when v_funding='store' and v_discount>0 then 'Venda entregue com cupom financiado pela loja' else 'Venda entregue' end)
    on conflict do nothing;

    insert into public.financial_ledger(order_id,beneficiary_type,beneficiary_user_id,store_id,amount,entry_type,status,available_at,notes)
    values(new.id,'platform',null,v_store,v_platform_net,'commission','available',now(),case when v_funding='platform' and v_discount>0 then 'Receita líquida da plataforma após cupom promocional' else 'Comissão da plataforma' end)
    on conflict do nothing;

    if new.courier_user_id is not null and coalesce(new.freight_amount,0)>0 then
      insert into public.financial_ledger(order_id,beneficiary_type,beneficiary_user_id,store_id,amount,entry_type,status,available_at,notes)
      values(new.id,'courier',new.courier_user_id,v_store,new.freight_amount,'freight_earning','available',now(),'Frete da entrega')
      on conflict do nothing;
    end if;

    update public.deliveries
    set freight_amount=coalesce(new.freight_amount,freight_amount,0),updated_at=now()
    where order_id=new.id;

    insert into public.audit_logs(actor_user_id,actor_role,action,entity_type,entity_id,metadata)
    values(auth.uid(),'system','settle','order',new.id::text,jsonb_build_object(
      'products_total',v_products,
      'discount_amount',v_discount,
      'coupon_funding',v_funding,
      'commission_rate',v_rate,
      'commission_amount',v_commission,
      'merchant_net_amount',v_merchant_net,
      'platform_subsidy_amount',v_platform_subsidy,
      'platform_net_revenue',v_platform_net,
      'freight_amount',coalesce(new.freight_amount,0),
      'store_id',v_store
    ));
  end if;
  return new;
end
$function$;
