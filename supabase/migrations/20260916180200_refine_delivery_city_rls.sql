-- Evita sobreposição de policies no cadastro de cidades de entrega.

drop policy if exists "delivery city coordinates public read" on public.delivery_city_coordinates;
drop policy if exists "delivery city coordinates admin manage" on public.delivery_city_coordinates;
drop policy if exists "delivery city coordinates admin insert" on public.delivery_city_coordinates;
drop policy if exists "delivery city coordinates admin update" on public.delivery_city_coordinates;
drop policy if exists "delivery city coordinates admin delete" on public.delivery_city_coordinates;

create policy "delivery city coordinates public read"
  on public.delivery_city_coordinates for select
  to anon, authenticated
  using (active = true or public.is_platform_admin());

create policy "delivery city coordinates admin insert"
  on public.delivery_city_coordinates for insert
  to authenticated
  with check (public.is_platform_admin());

create policy "delivery city coordinates admin update"
  on public.delivery_city_coordinates for update
  to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

create policy "delivery city coordinates admin delete"
  on public.delivery_city_coordinates for delete
  to authenticated
  using (public.is_platform_admin());
