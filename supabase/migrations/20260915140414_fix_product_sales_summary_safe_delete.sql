create or replace function public.refresh_product_sales_summary()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  delete from public.product_sales_summary
  where product_id is not null;

  insert into public.product_sales_summary(
    product_id,
    units_sold,
    delivered_orders,
    updated_at
  )
  select
    oi.product_id,
    coalesce(sum(oi.quantity), 0)::bigint,
    count(distinct oi.order_id)::bigint,
    now()
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where o.status_code = 'delivered'
    and oi.product_id is not null
  group by oi.product_id;

  return null;
end;
$function$;
