-- 6.8.56: إحصائيات نمو المنصة، قراءة مجمعة ومحميّة للمدير.
create or replace function public.admin_platform_growth_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare result jsonb;
begin
  if auth.uid() is null
     or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then
    raise exception 'admin access required' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'total_members', (select count(*) from auth.users),
    'new_members_7d', (select count(*) from auth.users where created_at >= now() - interval '7 days'),
    'new_members_30d', (select count(*) from auth.users where created_at >= now() - interval '30 days'),
    'active_members_30d', (select count(*) from auth.users where last_sign_in_at >= now() - interval '30 days'),
    'profile_count', (select count(*) from public.member_profiles),
    'topics_total', (select count(*) from public.community_topics),
    'replies_total', (select count(*) from public.topic_replies),
    'comments_total', (select count(*) from public.content_comments),
    'interactions_total', (select count(*) from public.community_topics) + (select count(*) from public.topic_replies) + (select count(*) from public.content_comments),
    'visits_total', (select count(*) from public.page_visits),
    'unique_visitors', (select count(distinct visitor_id) from public.page_visits),
    'visits_30d', (select count(*) from public.page_visits where created_at >= now() - interval '30 days'),
    'top_pages', (
      select coalesce(jsonb_agg(jsonb_build_object('page_path', page_path, 'visits', visit_count) order by visit_count desc, page_path), '[]'::jsonb)
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
revoke all on function public.admin_platform_growth_stats() from public;
revoke all on function public.admin_platform_growth_stats() from anon;
grant execute on function public.admin_platform_growth_stats() to authenticated;