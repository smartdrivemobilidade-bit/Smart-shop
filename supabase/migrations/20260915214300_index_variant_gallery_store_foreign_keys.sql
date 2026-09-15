create index if not exists idx_product_images_store
  on public.product_images(store_id);

create index if not exists idx_product_variants_store
  on public.product_variants(store_id);
