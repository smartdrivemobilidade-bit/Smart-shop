insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'banner-images',
  'banner-images',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp']::text[]
)
on conflict(id) do update
set public=excluded.public,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

create policy "banner images public read"
on storage.objects
for select
to public
using (bucket_id='banner-images');

create policy "banner images admin insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id='banner-images'
  and public.has_platform_role(array['master','admin','operations'])
);

create policy "banner images admin update"
on storage.objects
for update
to authenticated
using (
  bucket_id='banner-images'
  and public.has_platform_role(array['master','admin','operations'])
)
with check (
  bucket_id='banner-images'
  and public.has_platform_role(array['master','admin','operations'])
);

create policy "banner images admin delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id='banner-images'
  and public.has_platform_role(array['master','admin','operations'])
);