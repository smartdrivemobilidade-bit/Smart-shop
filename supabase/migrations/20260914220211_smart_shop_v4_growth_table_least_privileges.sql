revoke all on public.coupons from anon,authenticated;
grant select,insert,update,delete on public.coupons to authenticated;

revoke all on public.campaigns from anon,authenticated;
grant select on public.campaigns to anon;
grant select,insert,update,delete on public.campaigns to authenticated;

revoke all on public.favorite_stores from anon,authenticated;
grant select,insert,delete on public.favorite_stores to authenticated;

revoke all on public.store_business_hours from anon,authenticated;
grant select on public.store_business_hours to anon;
grant select,insert,update,delete on public.store_business_hours to authenticated;

revoke all on public.store_delivery_settings from anon,authenticated;
grant select on public.store_delivery_settings to anon;
grant select,insert,update,delete on public.store_delivery_settings to authenticated;

revoke all on public.store_quality_metrics from anon,authenticated;
grant select on public.store_quality_metrics to anon;
grant select,insert,update,delete on public.store_quality_metrics to authenticated;
