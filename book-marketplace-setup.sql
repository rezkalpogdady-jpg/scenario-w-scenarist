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
grant update, delete on public.book_marketplace_listings to authenticated;

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


-- إدارة إعلان البائع دون إنشاء حساب: رمز عشوائي قوي، ويُخزن تجزئته فقط.
create extension if not exists pgcrypto with schema extensions;

alter table public.book_marketplace_listings
  add column if not exists seller_token_hash text;

-- لا يُسمح بإعلان جديد دون تجزئة رمز إدارة قوي بطول SHA-256 hex.
drop policy if exists "Anyone can submit pending book listings" on public.book_marketplace_listings;
create policy "Anyone can submit pending book listings"
  on public.book_marketplace_listings
  for insert to anon, authenticated
  with check (
    status = 'pending'
    and seller_token_hash ~ '^[0-9a-f]{64}$'  );

-- لا نكشف تجزئة الرمز في استعلامات REST العامة أو لوحة الإدارة.
revoke select on public.book_marketplace_listings from anon, authenticated;
grant select (
  id,title,author_name,book_type,book_format,description,price,currency,
  seller_name,contact_phone,cover_path,cover_url,status,created_at,updated_at
) on public.book_marketplace_listings to anon, authenticated;

create or replace function public.seller_get_book_listing(p_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $seller_get$
declare v_row public.book_marketplace_listings%rowtype;
begin
  if p_token is null or length(p_token) <> 64 then return null; end if;
  select * into v_row
  from public.book_marketplace_listings
  where id = p_id
    and seller_token_hash = encode(extensions.digest(convert_to(p_token,'UTF8'),'sha256'),'hex');
  if not found then return null; end if;
  return jsonb_build_object(
    'id',v_row.id,'title',v_row.title,'author_name',v_row.author_name,
    'book_type',v_row.book_type,'book_format',v_row.book_format,
    'description',v_row.description,'price',v_row.price,'currency',v_row.currency,
    'seller_name',v_row.seller_name,'contact_phone',v_row.contact_phone,
    'cover_url',v_row.cover_url,'status',v_row.status,'created_at',v_row.created_at
  );
end;
$seller_get$;

create or replace function public.seller_delete_book_listing(p_id uuid, p_token text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $seller_delete$
declare v_deleted uuid;
begin
  if p_token is null or length(p_token) <> 64 then return false; end if;
  delete from public.book_marketplace_listings
  where id = p_id
    and seller_token_hash = encode(extensions.digest(convert_to(p_token,'UTF8'),'sha256'),'hex')
  returning id into v_deleted;
  return v_deleted is not null;
end;
$seller_delete$;


create or replace function public.seller_update_book_listing(
  p_id uuid, p_token text, p_title text, p_author_name text,
  p_book_type text, p_book_format text, p_description text,
  p_price numeric, p_currency text, p_seller_name text, p_contact_phone text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $seller_update$
declare v_updated uuid;
begin
  if p_token is null or length(p_token) <> 64 then return false; end if;
  update public.book_marketplace_listings
  set title = btrim(p_title),
      author_name = btrim(p_author_name),
      book_type = btrim(p_book_type),
      book_format = p_book_format,
      description = btrim(p_description),
      price = p_price,
      currency = p_currency,
      seller_name = btrim(p_seller_name),
      contact_phone = btrim(p_contact_phone),
      status = 'pending',
      updated_at = now()
  where id = p_id
    and seller_token_hash = encode(extensions.digest(convert_to(p_token,'UTF8'),'sha256'),'hex')
    and char_length(btrim(p_title)) between 2 and 180
    and char_length(btrim(p_author_name)) between 2 and 160
    and char_length(btrim(p_book_type)) between 2 and 80
    and p_book_format in ('ورقي','إلكتروني','ورقي وإلكتروني')
    and char_length(btrim(p_description)) between 10 and 2500
    and p_price between 0 and 10000000
    and p_currency in ('جنيه مصري','ريال سعودي','دولار أمريكي','درهم إماراتي')
    and char_length(btrim(p_seller_name)) between 2 and 120
    and char_length(btrim(p_contact_phone)) between 8 and 30
  returning id into v_updated;
  return v_updated is not null;
end;
$seller_update$;

revoke all on function public.seller_update_book_listing(uuid,text,text,text,text,text,text,numeric,text,text,text) from public;
grant execute on function public.seller_update_book_listing(uuid,text,text,text,text,text,text,numeric,text,text,text) to anon, authenticated;

revoke all on function public.seller_get_book_listing(uuid,text) from public;
revoke all on function public.seller_delete_book_listing(uuid,text) from public;
grant execute on function public.seller_get_book_listing(uuid,text) to anon, authenticated;
grant execute on function public.seller_delete_book_listing(uuid,text) to anon, authenticated;


-- حذف إعلانات الكتب: للمدير فقط.
drop policy if exists "Platform admins can delete book listings" on public.book_marketplace_listings;
create policy "Platform admins can delete book listings"
  on public.book_marketplace_listings
  for delete to authenticated
  using (private.is_platform_admin());

-- حذف أغلفة الكتب من مساحة التخزين: للمدير فقط.
drop policy if exists "Platform admins can delete book marketplace covers" on storage.objects;
create policy "Platform admins can delete book marketplace covers"
  on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'book-marketplace-covers'
    and private.is_platform_admin()
  );

commit;
