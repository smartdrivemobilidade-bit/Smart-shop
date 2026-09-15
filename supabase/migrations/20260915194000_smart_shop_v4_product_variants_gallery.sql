create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  image_url text not null,
  position integer not null default 0 check (position between 0 and 7),
  color_label text,
  created_at timestamptz not null default now(),
  unique (product_id, position)
);

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  color text,
  size text,
  sku text,
  stock integer not null default 0 check (stock >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (nullif(trim(coalesce(color, '')), '') is not null or nullif(trim(coalesce(size, '')), '') is not null),
  unique nulls not distinct (product_id, color, size)
);

alter table public.order_items
  add column if not exists variant_id uuid references public.product_variants(id) on delete set null,
  add column if not exists variant_label text,
  add column if not exists selected_options jsonb not null default '{}'::jsonb;

create index if not exists idx_product_images_product_position
  on public.product_images(product_id, position);
create index if not exists idx_product_variants_product_active
  on public.product_variants(product_id, active);
create index if not exists idx_order_items_variant
  on public.order_items(variant_id) where variant_id is not null;

alter table public.product_images enable row level security;
alter table public.product_variants enable row level security;

drop policy if exists "product images catalog read" on public.product_images;
create policy "product images catalog read"
on public.product_images for select to anon, authenticated
using (exists (
  select 1 from public.products p join public.stores s on s.id=p.store_id
  where p.id=product_id and p.active=true and s.active=true and s.approval_status='approved'
));

drop policy if exists "product images merchant insert" on public.product_images;
create policy "product images merchant insert"
on public.product_images for insert to authenticated
with check (public.is_store_member(store_id) and exists (
  select 1 from public.products p where p.id=product_id and p.store_id=store_id
));
drop policy if exists "product images merchant update" on public.product_images;
create policy "product images merchant update"
on public.product_images for update to authenticated
using (public.is_store_member(store_id))
with check (public.is_store_member(store_id) and exists (
  select 1 from public.products p where p.id=product_id and p.store_id=store_id
));
drop policy if exists "product images merchant delete" on public.product_images;
create policy "product images merchant delete"
on public.product_images for delete to authenticated
using (public.is_store_member(store_id));

drop policy if exists "product variants catalog read" on public.product_variants;
create policy "product variants catalog read"
on public.product_variants for select to anon, authenticated
using (active=true and exists (
  select 1 from public.products p join public.stores s on s.id=p.store_id
  where p.id=product_id and p.active=true and s.active=true and s.approval_status='approved'
));
drop policy if exists "product variants merchant insert" on public.product_variants;
create policy "product variants merchant insert"
on public.product_variants for insert to authenticated
with check (public.is_store_member(store_id) and exists (
  select 1 from public.products p where p.id=product_id and p.store_id=store_id
));
drop policy if exists "product variants merchant update" on public.product_variants;
create policy "product variants merchant update"
on public.product_variants for update to authenticated
using (public.is_store_member(store_id))
with check (public.is_store_member(store_id) and exists (
  select 1 from public.products p where p.id=product_id and p.store_id=store_id
));
drop policy if exists "product variants merchant delete" on public.product_variants;
create policy "product variants merchant delete"
on public.product_variants for delete to authenticated
using (public.is_store_member(store_id));

grant select on public.product_images, public.product_variants to anon;
grant select, insert, update, delete on public.product_images, public.product_variants to authenticated;

-- A soma das variações mantém o estoque total do produto sincronizado.
create or replace function public.sync_product_stock_from_variants()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_product_id uuid := coalesce(new.product_id, old.product_id);
begin
  update public.products
  set stock = coalesce((
    select sum(v.stock) from public.product_variants v
    where v.product_id=v_product_id and v.active=true
  ), 0), updated_at=now()
  where id=v_product_id;
  return coalesce(new, old);
end
$function$;

drop trigger if exists trg_sync_product_stock_from_variants on public.product_variants;
create trigger trg_sync_product_stock_from_variants
after insert or update of stock, active or delete on public.product_variants
for each row execute function public.sync_product_stock_from_variants();

revoke all on function public.sync_product_stock_from_variants() from public, anon, authenticated;

