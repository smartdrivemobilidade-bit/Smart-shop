update public.stores
set category = coalesce(category, 'Moda'),
    phone = coalesce(phone, '(31) 00000-0000'),
    whatsapp = coalesce(whatsapp, '(31) 00000-0000'),
    email = coalesce(email, 'bella.moda@teste.smartshop.local'),
    updated_at = now()
where id = 'f9526757-1314-4c03-9fb3-c11532461607'
  and name = 'Bella Moda';
