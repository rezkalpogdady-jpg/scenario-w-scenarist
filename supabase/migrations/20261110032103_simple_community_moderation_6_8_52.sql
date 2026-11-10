-- 6.8.52: simple community moderation (delete content / block member posting)
create table if not exists public.member_posting_blocks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.member_posting_blocks enable row level security;
revoke all on public.member_posting_blocks from anon;
grant select, insert, delete on public.member_posting_blocks to authenticated;
drop policy if exists "Admins can manage member posting blocks" on public.member_posting_blocks;
create policy "Admins can manage member posting blocks"
on public.member_posting_blocks for all to authenticated
using (private.is_platform_admin())
with check (private.is_platform_admin());
drop policy if exists "Members can read own posting block" on public.member_posting_blocks;
create policy "Members can read own posting block"
on public.member_posting_blocks for select to authenticated
using ((select auth.uid()) = user_id);
drop policy if exists "Members can submit community topics" on public.community_topics;
create policy "Members can submit community topics"
on public.community_topics for insert to authenticated
with check ((select auth.uid()) = user_id and status = 'pending'
  and not exists (select 1 from public.member_posting_blocks b where b.user_id = (select auth.uid())));
drop policy if exists "Members can submit topic replies" on public.topic_replies;
create policy "Members can submit topic replies"
on public.topic_replies for insert to authenticated
with check ((select auth.uid()) = user_id and status = 'pending'
  and not exists (select 1 from public.member_posting_blocks b where b.user_id = (select auth.uid())));
drop policy if exists "Members can submit content comments" on public.content_comments;
create policy "Members can submit content comments"
on public.content_comments for insert to authenticated
with check ((select auth.uid()) = user_id and status = 'pending'
  and not exists (select 1 from public.member_posting_blocks b where b.user_id = (select auth.uid())));
create index if not exists member_posting_blocks_created_at_idx
on public.member_posting_blocks (created_at desc);