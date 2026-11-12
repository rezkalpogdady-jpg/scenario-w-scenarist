-- 2026-11-12: member-number authentication and member-only sections
alter table public.member_profiles
  add column if not exists member_number text,
  add column if not exists gender text,
  add column if not exists birth_date date;

alter table public.member_profiles
  add constraint member_profiles_gender_check
  check (gender is null or gender in ('male','female'));

create unique index if not exists member_profiles_member_number_uidx
  on public.member_profiles(member_number)
  where member_number is not null;

create table if not exists public.member_login_directory (
  member_number text primary key
    check (member_number ~ '^[0-9]{8}$'),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.member_login_directory enable row level security;
revoke all on public.member_login_directory from anon, authenticated;
grant all on public.member_login_directory to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('member-avatars','member-avatars',true,3145728,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true, file_size_limit=3145728,
  allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "Read published crime stories or admin" on public.crime_stories;
create policy "Members read published crime stories"
on public.crime_stories for select
to authenticated
using (is_published = true or coalesce((select auth.jwt()->'app_metadata'->>'role')='admin',false));

drop policy if exists "Public read published site content" on public.site_content;
create policy "Public read non-restricted published site content"
on public.site_content for select
to anon, authenticated
using (
  published = true
  and (
    content_type not in ('stories','films')
    or (select auth.uid()) is not null
  )
);
