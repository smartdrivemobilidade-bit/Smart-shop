alter table public.merchant_applications
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists terms_version text;

alter table public.merchant_applications
  add constraint merchant_applications_terms_required_check
  check (
    status not in ('submitted','under_review','documents_pending','approved')
    or (terms_accepted_at is not null and nullif(trim(terms_version),'') is not null)
  );

comment on column public.merchant_applications.terms_accepted_at
  is 'Momento em que o candidato aceitou os Termos de Uso e as regras operacionais.';
comment on column public.merchant_applications.terms_version
  is 'Versão dos termos aceita pelo candidato.';