revoke all privileges on table public.merchant_applications from anon;
revoke references, trigger, truncate on table public.merchant_applications from authenticated;
grant select, insert, update on table public.merchant_applications to authenticated;

revoke references, trigger, truncate on table public.partner_documents from anon;
revoke references, trigger, truncate on table public.partner_documents from authenticated;
grant select, insert, update on table public.partner_documents to authenticated;