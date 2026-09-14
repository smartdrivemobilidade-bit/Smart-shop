do $$
declare r record;
begin
 for r in select tablename from pg_tables where schemaname='public' loop
  execute format('revoke references, trigger, truncate on table public.%I from anon, authenticated',r.tablename);
 end loop;
end $$;
revoke all on public.favorites from anon;
revoke all on public.favorites from authenticated;
grant select,insert,delete on public.favorites to authenticated;
revoke all on public.store_favorites from anon;
revoke all on public.store_favorites from authenticated;
grant select,insert,delete on public.store_favorites to authenticated;
