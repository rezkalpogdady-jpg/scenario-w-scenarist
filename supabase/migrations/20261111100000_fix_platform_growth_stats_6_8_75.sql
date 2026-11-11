
create or replace function public.admin_platform_growth_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  result jsonb;
begin
  if auth.uid() is null
     or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then
    raise exception 'admin access required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'total_members', (
      select count(*) from auth.users u
      where coalesce(u.raw_app_meta_data ->> 'role', '') <> 'admin'
    ),
    'new_members_7d', (
      select count(*) from auth.users u
      where coalesce(u.raw_app_meta_data ->> 'role', '') <> 'admin'
        and u.created_at >= now() - interval '7 days'
    ),
    'new_members_30d', (
      select count(*) from auth.users u
      where coalesce(u.raw_app_meta_data ->> 'role', '') <> 'admin'
        and u.created_at >= now() - interval '30 days'
    ),
    'active_members_30d', (
      select count(*) from auth.users u
      where coalesce(u.raw_app_meta_data ->> 'role', '') <> 'admin'
        and u.last_sign_in_at >= now() - interval '30 days'
    ),
    'profile_count', (
      select count(*)
      from public.member_profiles mp
      join auth.users u on u.id = mp.user_id
      where coalesce(u.raw_app_meta_data ->> 'role', '') <> 'admin'
    ),
    'topics_total', (
      select count(*) from public.community_topics where status = 'approved'
    ),
    'replies_total', (
      select count(*) from public.topic_replies where status = 'approved'
    ),
    'comments_total', (
      select count(*) from public.content_comments where status = 'approved'
    ),
    'submissions_total', (
      select count(*) from public.community_submissions where status = 'approved'
    ),
    'interactions_total',
      (select count(*) from public.community_topics where status = 'approved')
      + (select count(*) from public.topic_replies where status = 'approved')
      + (select count(*) from public.content_comments where status = 'approved')
      + (select count(*) from public.community_submissions where status = 'approved'),
    'visits_total', (select count(*) from public.page_visits),
    'unique_visitors', (
      select count(distinct visitor_id)
      from public.page_visits
      where nullif(visitor_id, '') is not null
    ),
    'visits_30d', (
      select count(*) from public.page_visits
      where created_at >= now() - interval '30 days'
    ),
    'top_pages', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object('page_path', page_path, 'visits', visit_count)
          order by visit_count desc, page_path
        ),
        '[]'::jsonb
      )
      from (
        select coalesce(nullif(page_path, ''), '/') as page_path, count(*) as visit_count
        from public.page_visits
        group by coalesce(nullif(page_path, ''), '/')
        order by count(*) desc, coalesce(nullif(page_path, ''), '/')
        limit 6
      ) popular_pages
    )
  ) into result;

  return result;
end;
$function$;

revoke all on function public.admin_platform_growth_stats() from public, anon;
grant execute on function public.admin_platform_growth_stats() to authenticated, service_role;
