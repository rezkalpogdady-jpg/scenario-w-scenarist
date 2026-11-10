create table public.community_topic_likes (
  topic_id uuid not null references public.community_topics(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint community_topic_likes_pkey primary key (topic_id, user_id)
);

create index community_topic_likes_user_id_idx
  on public.community_topic_likes (user_id);

alter table public.community_topic_likes enable row level security;

create policy "Members can like approved community topics"
  on public.community_topic_likes
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.community_topics t
      where t.id = topic_id
        and t.status = 'approved'
    )
  );

create policy "Members can remove their own community topic likes"
  on public.community_topic_likes
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant insert, delete on public.community_topic_likes to authenticated;

create or replace function public.get_community_topic_like_stats(p_topic_ids uuid[])
returns table (topic_id uuid, like_count bigint, liked_by_me boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if p_topic_ids is null or cardinality(p_topic_ids) = 0 then
    return;
  end if;

  if cardinality(p_topic_ids) > 100 then
    raise exception 'Too many topic IDs' using errcode = '22023';
  end if;

  return query
  select
    t.id,
    count(l.user_id),
    coalesce(bool_or(l.user_id = v_user_id), false)
  from public.community_topics t
  left join public.community_topic_likes l
    on l.topic_id = t.id
  where t.id = any(p_topic_ids)
    and t.status = 'approved'
  group by t.id;
end;
$$;

revoke all on function public.get_community_topic_like_stats(uuid[]) from public, anon;
grant execute on function public.get_community_topic_like_stats(uuid[]) to authenticated;
