create policy "order_verification_codes_no_direct_access"
on public.order_verification_codes
as restrictive
for all
to anon, authenticated
using (false)
with check (false);