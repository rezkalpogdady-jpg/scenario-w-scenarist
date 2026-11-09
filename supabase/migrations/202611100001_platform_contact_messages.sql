-- Platform contact inbox
create table if not exists public.platform_contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 100),
  email text not null check (char_length(btrim(email)) between 5 and 254),
  subject text not null check (char_length(btrim(subject)) between 2 and 120),
  message text not null check (char_length(btrim(message)) between 10 and 5000),
  status text not null default 'new' check (status in ('new','read','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.platform_contact_messages enable row level security;
grant insert on public.platform_contact_messages to anon, authenticated;
grant select, update on public.platform_contact_messages to authenticated;
drop policy if exists "Public can send platform contact messages" on public.platform_contact_messages;
create policy "Public can send platform contact messages"
on public.platform_contact_messages for insert to anon, authenticated
with check (
  char_length(btrim(name)) between 2 and 100
  and char_length(btrim(email)) between 5 and 254
  and char_length(btrim(subject)) between 2 and 120
  and char_length(btrim(message)) between 10 and 5000
  and status = 'new'
);
drop policy if exists "Platform admins can read contact messages" on public.platform_contact_messages;
create policy "Platform admins can read contact messages"
on public.platform_contact_messages for select to authenticated
using ((auth.jwt()->'app_metadata'->>'role') = 'admin');
drop policy if exists "Platform admins can update contact messages" on public.platform_contact_messages;
create policy "Platform admins can update contact messages"
on public.platform_contact_messages for update to authenticated
using ((auth.jwt()->'app_metadata'->>'role') = 'admin')
with check ((auth.jwt()->'app_metadata'->>'role') = 'admin');
create index if not exists platform_contact_messages_created_at_idx
on public.platform_contact_messages (created_at desc);
