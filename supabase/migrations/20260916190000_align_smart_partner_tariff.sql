-- Alinha o frete das entregas do parceiro à tarifa padrão escolhida pela operação.

insert into public.platform_settings(key, value, updated_at)
values
  ('smart_partner_base_freight', '6'::jsonb, now()),
  ('smart_partner_per_km', '2.90'::jsonb, now()),
  ('smart_partner_min_freight', '12'::jsonb, now()),
  ('smart_partner_max_freight', '125'::jsonb, now())
on conflict (key) do update
set value=excluded.value, updated_at=now();
