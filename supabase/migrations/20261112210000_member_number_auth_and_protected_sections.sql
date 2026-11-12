-- 2026-11-12: private member-number authentication and member-only sections
-- Member numbers and personal details are kept outside the publicly readable profile table.
create table if not exists public.member_login_directory (
  member_number text primary key check (member_number ~ '^[0-9]{8}$'),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.member_login_directory enable row level security;
revoke all on public.member_login_directory from anon, authenticated;
grant all on public.member_login_directory to service_role;

create table if not exists public.member_private_details (
  user_id uuid primary key references auth.users(id) on delete cascade,
  gender text not null check (gender in ('male','female')),
  birth_date date not null check (birth_date <= current_date),
  created_at timestamptz not null default now()
);
alter table public.member_private_details enable row level security;
revoke all on public.member_private_details from anon, authenticated;
grant all on public.member_private_details to service_role;

-- Backfill existing member accounts with unique IDs and put the ID in trusted app metadata.
with numbered as (
  select user_id, row_number() over (order by created_at, user_id) as rn
  from public.member_profiles
  where user_id not in (select user_id from public.member_login_directory)
)
insert into public.member_login_directory (member_number, user_id)
select (10000000 + rn)::text, user_id
from numbered
on conflict do nothing;

update auth.users as users
set raw_app_meta_data =
  coalesce(users.raw_app_meta_data, '{}'::jsonb)
  || jsonb_build_object('member_number', directory.member_number)
from public.member_login_directory as directory
where users.id = directory.user_id
  and coalesce(users.raw_app_meta_data->>'member_number','') <> directory.member_number;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('member-avatars','member-avatars',true,3145728,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true, file_size_limit=3145728,
  allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "Read published crime stories or admin" on public.crime_stories;
drop policy if exists "Members read published crime stories" on public.crime_stories;
create policy "Members read published crime stories"
on public.crime_stories for select
to authenticated
using (
  (is_published = true and status = 'approved')
  or coalesce((select auth.jwt()->'app_metadata'->>'role')='admin',false)
);

drop policy if exists "Submit crime stories or admin publish" on public.crime_stories;
create policy "Members submit crime stories or admin publish"
on public.crime_stories for insert
to authenticated
with check (
  coalesce((select auth.jwt()->'app_metadata'->>'role')='admin',false)
  or (
    is_published = false
    and status = 'pending'
    and char_length(btrim(title)) between 3 and 180
    and content is not null
    and char_length(btrim(content)) between 40 and 30000
    and (author_name is null or char_length(btrim(author_name)) <= 120)
    and (category is null or char_length(btrim(category)) <= 80)
  )
);

drop policy if exists "Public read published site content" on public.site_content;
drop policy if exists "Public read non-restricted published site content" on public.site_content;
create policy "Members read non-restricted published site content"
on public.site_content for select
to anon, authenticated
using (
  published = true
  and (
    content_type not in ('stories','films')
    or (select auth.uid()) is not null
  )
);
