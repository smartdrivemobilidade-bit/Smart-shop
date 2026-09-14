create index if not exists idx_campaigns_created_by on public.campaigns(created_by) where created_by is not null;
create index if not exists idx_coupons_store_id on public.coupons(store_id) where store_id is not null;
create index if not exists idx_delivery_location_events_courier on public.delivery_location_events(courier_user_id);
create index if not exists idx_delivery_location_events_delivery on public.delivery_location_events(delivery_id);
create index if not exists idx_favorite_stores_store on public.favorite_stores(store_id);
create index if not exists idx_loyalty_transactions_order on public.loyalty_transactions(order_id) where order_id is not null;
create index if not exists idx_loyalty_transactions_user on public.loyalty_transactions(user_id);
create index if not exists idx_store_favorites_store on public.store_favorites(store_id);

drop policy if exists "favorite_stores_select_own" on public.favorite_stores;
drop policy if exists "favorite_stores_insert_own" on public.favorite_stores;
drop policy if exists "favorite_stores_delete_own" on public.favorite_stores;
create policy favorite_stores_select_own on public.favorite_stores for select to authenticated using(user_id=(select auth.uid()));
create policy favorite_stores_insert_own on public.favorite_stores for insert to authenticated with check(user_id=(select auth.uid()));
create policy favorite_stores_delete_own on public.favorite_stores for delete to authenticated using(user_id=(select auth.uid()));

drop policy if exists "notifications own read" on public.notifications;
drop policy if exists "notifications own mark read" on public.notifications;
create policy "notifications own read" on public.notifications for select to authenticated using(user_id=(select auth.uid()));

drop policy if exists "order status history customer read" on public.order_status_history;

drop policy if exists "reviews authenticated read" on public.reviews;
create policy "reviews authenticated read" on public.reviews for select to authenticated using(active=true or user_id=(select auth.uid()) or public.is_platform_admin());

drop policy if exists "courier own delivery location insert" on public.delivery_location_events;
drop policy if exists "delivery location related read" on public.delivery_location_events;
create policy "courier own delivery location insert" on public.delivery_location_events for insert to authenticated
with check(courier_user_id=(select auth.uid()) and exists(select 1 from public.deliveries d where d.id=delivery_id and d.courier_user_id=(select auth.uid())));
create policy "delivery location related read" on public.delivery_location_events for select to authenticated
using(courier_user_id=(select auth.uid()) or exists(select 1 from public.deliveries d join public.orders o on o.id=d.order_id where d.id=delivery_id and o.user_id=(select auth.uid())) or exists(select 1 from public.deliveries d join public.store_members sm on sm.store_id=d.store_id where d.id=delivery_id and sm.user_id=(select auth.uid())) or public.has_platform_role(array['master','admin','operations','support']));

drop policy if exists "support_tickets_owner_select_v4" on public.support_tickets;
drop policy if exists "support_tickets_owner_insert_v4" on public.support_tickets;
drop policy if exists "support_messages_ticket_owner_select_v4" on public.support_messages;
drop policy if exists "support_messages_ticket_owner_insert_v4" on public.support_messages;

drop policy if exists "users read own loyalty account" on public.loyalty_accounts;
drop policy if exists "admins manage loyalty accounts" on public.loyalty_accounts;
create policy "loyalty accounts read" on public.loyalty_accounts for select to authenticated using(user_id=(select auth.uid()) or public.is_platform_admin());
create policy "admins insert loyalty accounts" on public.loyalty_accounts for insert to authenticated with check(public.is_platform_admin());
create policy "admins update loyalty accounts" on public.loyalty_accounts for update to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());
create policy "admins delete loyalty accounts" on public.loyalty_accounts for delete to authenticated using(public.is_platform_admin());

drop policy if exists "users read own loyalty transactions" on public.loyalty_transactions;
drop policy if exists "admins manage loyalty transactions" on public.loyalty_transactions;
create policy "loyalty transactions read" on public.loyalty_transactions for select to authenticated using(user_id=(select auth.uid()) or public.is_platform_admin());
create policy "admins insert loyalty transactions" on public.loyalty_transactions for insert to authenticated with check(public.is_platform_admin());
create policy "admins update loyalty transactions" on public.loyalty_transactions for update to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());
create policy "admins delete loyalty transactions" on public.loyalty_transactions for delete to authenticated using(public.is_platform_admin());

drop policy if exists "users manage own store favorites" on public.store_favorites;
drop policy if exists "store members read followers" on public.store_favorites;
create policy "store favorites read" on public.store_favorites for select to authenticated using(user_id=(select auth.uid()) or public.is_store_member(store_id) or public.has_platform_role(array['master','admin','operations']));
create policy "store favorites insert own" on public.store_favorites for insert to authenticated with check(user_id=(select auth.uid()));
create policy "store favorites delete own" on public.store_favorites for delete to authenticated using(user_id=(select auth.uid()));

drop policy if exists "public read store business hours" on public.store_business_hours;
drop policy if exists "store members manage business hours" on public.store_business_hours;
create policy "store business hours public read" on public.store_business_hours for select to anon,authenticated using(true);
create policy "store members insert business hours" on public.store_business_hours for insert to authenticated with check(public.is_store_member(store_id));
create policy "store members update business hours" on public.store_business_hours for update to authenticated using(public.is_store_member(store_id)) with check(public.is_store_member(store_id));
create policy "store members delete business hours" on public.store_business_hours for delete to authenticated using(public.is_store_member(store_id));

drop policy if exists "public read store delivery settings" on public.store_delivery_settings;
drop policy if exists "store members manage delivery settings" on public.store_delivery_settings;
create policy "store delivery settings public read" on public.store_delivery_settings for select to anon,authenticated using(true);
create policy "store members insert delivery settings" on public.store_delivery_settings for insert to authenticated with check(public.is_store_member(store_id));
create policy "store members update delivery settings" on public.store_delivery_settings for update to authenticated using(public.is_store_member(store_id)) with check(public.is_store_member(store_id));
create policy "store members delete delivery settings" on public.store_delivery_settings for delete to authenticated using(public.is_store_member(store_id));

drop policy if exists "public read store quality metrics" on public.store_quality_metrics;
drop policy if exists "admins manage quality metrics" on public.store_quality_metrics;
create policy "store quality public read" on public.store_quality_metrics for select to anon,authenticated using(true);
create policy "admins insert quality metrics" on public.store_quality_metrics for insert to authenticated with check(public.is_platform_admin());
create policy "admins update quality metrics" on public.store_quality_metrics for update to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());
create policy "admins delete quality metrics" on public.store_quality_metrics for delete to authenticated using(public.is_platform_admin());

drop policy if exists "public read active campaigns" on public.campaigns;
drop policy if exists "admins manage campaigns" on public.campaigns;
create policy "campaigns anon read active" on public.campaigns for select to anon using(active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>=now()));
create policy "campaigns authenticated read" on public.campaigns for select to authenticated using((active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>=now())) or public.has_platform_role(array['master','admin','operations']));
create policy "admins insert campaigns" on public.campaigns for insert to authenticated with check(public.has_platform_role(array['master','admin','operations']));
create policy "admins update campaigns" on public.campaigns for update to authenticated using(public.has_platform_role(array['master','admin','operations'])) with check(public.has_platform_role(array['master','admin','operations']));
create policy "admins delete campaigns" on public.campaigns for delete to authenticated using(public.has_platform_role(array['master','admin','operations']));
