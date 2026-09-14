drop policy if exists "authenticated lookup active referral codes" on public.referral_codes;
drop policy if exists "users create own referral codes" on public.referral_codes;
drop policy if exists "users read own referral codes" on public.referral_codes;
drop policy if exists "referred user claims referral" on public.referrals;
drop policy if exists "users read own referral activity" on public.referrals;

drop policy if exists referral_codes_read on public.referral_codes;
drop policy if exists referrals_read on public.referrals;
drop policy if exists store_referrals_read on public.store_referrals;

create policy referral_codes_read on public.referral_codes for select to authenticated
using(owner_user_id=(select auth.uid()) or public.has_platform_role(array['master','admin','operations']));
create policy referrals_read on public.referrals for select to authenticated
using(referrer_user_id=(select auth.uid()) or referred_user_id=(select auth.uid()) or public.has_platform_role(array['master','admin','operations']));
create policy store_referrals_read on public.store_referrals for select to authenticated
using(referrer_user_id=(select auth.uid()) or public.has_platform_role(array['master','admin','operations']));

create index if not exists idx_referrals_referrer_user_id on public.referrals(referrer_user_id);
create index if not exists idx_referrals_referral_code_id on public.referrals(referral_code_id);
create index if not exists idx_referrals_first_order_id on public.referrals(first_order_id) where first_order_id is not null;
create index if not exists idx_referrals_reward_coupon_id on public.referrals(reward_coupon_id) where reward_coupon_id is not null;
create index if not exists idx_store_referrals_referrer_user_id on public.store_referrals(referrer_user_id);
create index if not exists idx_store_referrals_converted_store_id on public.store_referrals(converted_store_id) where converted_store_id is not null;
create index if not exists idx_store_referrals_reviewed_by on public.store_referrals(reviewed_by) where reviewed_by is not null;
