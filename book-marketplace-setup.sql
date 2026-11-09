-- إعداد سوق الكتب للبيع — سيناريو وسيناريست
-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor قبل نشر نسخة الموقع.

begin;

create table if not exists public.book_marketplace_listings (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 2 and 180),
  author_name text not null check (char_length(btrim(author_name)) between 2 and 160),
  book_type text not null check (char_length(btrim(book_type)) between 2 and 80),
  book_format text not null check (book_format in ('ورقي','إلكتروني','ورقي وإلكتروني')),
  description text not null check (char_length(btrim(description)) between 10 and 2500),
  price numeric(10,2) not null check (price >= 0),
  currency text not null check (currency in ('جنيه مصري','ريال سعودي','دولار أمريكي','درهم إماراتي')),
  seller_name text not null check (char_length(btrim(seller_name)) between 2 and 120),
  contact_phone text not null check (char_length(btrim(contact_phone)) between 8 and 30),
  cover_path text not null,
  cover_url text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.book_marketplace_listings enable row level security;

grant select, insert on public.book_marketplace_listings to anon, authenticated;
grant update on public.book_marketplace_listings to authenticated;

drop policy if exists "Public can view approved book listings" on public.book_marketplace_listings;
create policy "Public can view approved book listings"
  on public.book_marketplace_listings
  for select to anon, authenticated
  using (status = 'approved');

drop policy if exists "Anyone can submit pending book listings" on public.book_marketplace_listings;
create policy "Anyone can submit pending book listings"
  on public.book_marketplace_listings
  for insert to anon, authenticated
  with check (status = 'pending');

drop policy if exists "Platform admins can review book listings" on public.book_marketplace_listings;
create policy "Platform admins can review book listings"
  on public.book_marketplace_listings
  for select to authenticated
  using (private.is_platform_admin());

drop policy if exists "Platform admins can update book listing status" on public.book_marketplace_listings;
create policy "Platform admins can update book listing status"
  on public.book_marketplace_listings
  for update to authenticated
  using (private.is_platform_admin())
  with check (private.is_platform_admin());

-- مساحة مستقلة لأغلفة الكتب؛ لا نعيد استخدام مساحة صور الأعضاء.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'book-marketplace-covers',
  'book-marketplace-covers',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public can view book marketplace covers" on storage.objects;
create policy "Public can view book marketplace covers"
  on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'book-marketplace-covers');

drop policy if exists "Anyone can upload pending book marketplace covers" on storage.objects;
create policy "Anyone can upload pending book marketplace covers"
  on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'book-marketplace-covers'
    and (storage.foldername(name))[1] = 'pending'
    and lower(storage.extension(name)) = any (array['jpg','jpeg','png','webp'])
  );

commit;
