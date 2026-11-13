-- Content engagement analytics v1
-- Draft migration: reviewed in GitHub branch; do not apply to production until approved.
begin;

create schema if not exists scenario_analytics_private;
revoke all on schema scenario_analytics_private from public;
grant usage on schema scenario_analytics_private to anon, authenticated;

create table if not exists public.content_engagement_events (
  id bigint generated always as identity primary key,
  content_type text not null,
  content_id text not null,
  event_type text not null check (event_type in ('impression','open')),
  viewer_id uuid not null,
  occurred_at timestamptz not null default now()
);

create index if not exists content_engagement_lookup_idx
  on public.content_engagement_events (content_type, content_id, event_type, occurred_at desc);
create index if not exists content_engagement_viewer_idx
  on public.content_engagement_events (viewer_id, occurred_at desc);

alter table public.content_engagement_events enable row level security;
revoke all on table public.content_engagement_events from public, anon, authenticated;

create or replace function scenario_analytics_private.record_public_content_event(
  p_content_type text,
  p_content_id text,
  p_event_type text,
  p_viewer_id uuid
) returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  content_is_public boolean := false;
  lock_key bigint;
begin
  if p_content_type is null or p_content_id is null or p_viewer_id is null
     or p_content_type not in ('academy','crime_story','stories','scenario','archive')
     or p_event_type is null or p_event_type not in ('impression','open')
     or length(p_content_id) > 80 then
    return false;
  end if;

  if p_content_type = 'crime_story' then
    select exists (
      select 1 from public.crime_stories s
      where s.id::text = p_content_id and s.is_published = true and s.status = 'approved'
    ) into content_is_public;
  elsif p_content_type = 'scenario' then
    select exists (
      select 1 from public.scenario_scripts s
      where s.id::text = p_content_id and s.published = true
        and s.rights_confirmed = true and coalesce(s.rights_status,'') <> 'unverified'
        and nullif(s.rights_holder,'') is not null
    ) into content_is_public;
  elsif p_content_type = 'scenario' then
    select exists (
      select 1 from public.scenario_scripts s
      where s.id::text = p_content_id and s.published = true
        and s.rights_confirmed = true and coalesce(s.rights_status,'') <> 'unverified'
        and nullif(s.rights_holder,'') is not null
    ) into content_is_public;
  elsif p_content_type in ('academy','stories','archive') then
    select exists (
      select 1 from public.site_content c
      where c.id::text = p_content_id
        and c.content_type = p_content_type
        and c.published = true
        and (p_content_type <> 'archive' or coalesce(c.extra_data->>'media_kind','') <> 'video')
    ) into content_is_public;
  end if;

  if not content_is_public then
    return false;
  end if;

  lock_key := pg_catalog.hashtextextended(
    p_content_type || ':' || p_content_id || ':' || p_event_type || ':' || p_viewer_id::text, 0
  );
  perform pg_catalog.pg_advisory_xact_lock(lock_key);

  if exists (
    select 1 from public.content_engagement_events e
    where e.content_type = p_content_type and e.content_id = p_content_id
      and e.event_type = p_event_type and e.viewer_id = p_viewer_id
      and e.occurred_at > now() - interval '30 minutes'
  ) then
    return true;
  end if;

  insert into public.content_engagement_events(content_type,content_id,event_type,viewer_id)
  values (p_content_type,p_content_id,p_event_type,p_viewer_id);
  return true;
end;
$function$;

revoke all on function scenario_analytics_private.record_public_content_event(text,text,text,uuid) from public;
grant execute on function scenario_analytics_private.record_public_content_event(text,text,text,uuid) to anon, authenticated;

create or replace function public.record_public_content_event(
  p_content_type text,
  p_content_id text,
  p_event_type text,
  p_viewer_id uuid
) returns boolean
language sql
security invoker
set search_path = ''
as $function$
  select scenario_analytics_private.record_public_content_event(p_content_type,p_content_id,p_event_type,p_viewer_id);
$function$;

revoke all on function public.record_public_content_event(text,text,text,uuid) from public;
grant execute on function public.record_public_content_event(text,text,text,uuid) to anon, authenticated;

create or replace function scenario_analytics_private.admin_content_engagement_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare result jsonb;
begin
  if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','') <> 'admin' then
    raise exception 'admin access required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_events desc, x.title), '[]'::jsonb)
  into result
  from (
    select e.content_type, e.content_id, e.event_type,
      coalesce(sc.title, cs.title, ss.title, 'محتوى منشور') as title,
      count(*)::bigint as total_events,
      count(distinct e.viewer_id)::bigint as unique_viewers,
      count(*) filter (where e.occurred_at >= now() - interval '7 days')::bigint as events_7d,
      count(*) filter (where e.occurred_at >= now() - interval '30 days')::bigint as events_30d
    from public.content_engagement_events e
    left join public.site_content sc
      on sc.id::text = e.content_id and sc.content_type = e.content_type
      and e.content_type in ('academy','stories','archive')
    left join public.crime_stories cs
      on e.content_type = 'crime_story' and cs.id::text = e.content_id
    left join public.scenario_scripts ss
      on e.content_type = 'scenario' and ss.id::text = e.content_id
    where e.content_type in ('academy','crime_story','stories','scenario','archive')
    group by e.content_type,e.content_id,e.event_type,sc.title,cs.title,ss.title

    union all

    select e.content_type, null::text as content_id, e.event_type,
      'إجمالي القسم'::text as title,
      count(*)::bigint as total_events,
      count(distinct e.viewer_id)::bigint as unique_viewers,
      count(*) filter (where e.occurred_at >= now() - interval '7 days')::bigint as events_7d,
      count(*) filter (where e.occurred_at >= now() - interval '30 days')::bigint as events_30d
    from public.content_engagement_events e
    where e.content_type in ('academy','crime_story','stories','scenario','archive')
    group by e.content_type,e.event_type
  ) x;
  return result;
end;
$function$;

revoke all on function scenario_analytics_private.admin_content_engagement_stats() from public;
grant execute on function scenario_analytics_private.admin_content_engagement_stats() to authenticated;

create or replace function public.admin_content_engagement_stats()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select scenario_analytics_private.admin_content_engagement_stats();
$function$;

revoke all on function public.admin_content_engagement_stats() from public;
grant execute on function public.admin_content_engagement_stats() to authenticated;

commit;
