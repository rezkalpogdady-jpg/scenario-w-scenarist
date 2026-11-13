-- Harden member account integrity and SECURITY DEFINER execution.
-- Note: member-auth baseline already has cascading user foreign keys; the follow-up
-- migration removes these defensive duplicate declarations after history replay.

ALTER TABLE public.member_login_directory
  ADD CONSTRAINT member_login_directory_user_id_auth_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.member_private_details
  ADD CONSTRAINT member_private_details_user_id_auth_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER FUNCTION public.seller_delete_book_listing(uuid, text) SET search_path = '';
ALTER FUNCTION public.seller_get_book_listing(uuid, text) SET search_path = '';
ALTER FUNCTION public.seller_update_book_listing(uuid, text, text, text, text, text, text, numeric, text, text, text) SET search_path = '';
ALTER FUNCTION public.consume_member_auth_attempt(text, text, integer, integer) SET search_path = '';

CREATE OR REPLACE FUNCTION public.admin_content_view_stats()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
declare result jsonb;
begin
  if auth.uid() is null
     or coalesce(auth.jwt()->'app_metadata'->>'role','') <> 'admin'
     or not exists (select 1 from public.admin_users where user_id = (select auth.uid())) then
    raise exception 'admin access required' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'content_type',content_type,'content_label',content_label,
    'content_id',content_id,'title',title,'unique_views',unique_views
  ) order by unique_views desc,title),'[]'::jsonb)
  into result
  from (
    select 'academy'::text content_type,'محاضرة'::text content_label,
      c.id content_id,c.title,count(v.viewer_id)::bigint unique_views
    from public.site_content c
    left join public.content_views v on v.content_type='academy' and v.content_id=c.id
    where c.content_type='academy' and c.published=true group by c.id,c.title
    union all
    select 'film','فيديو / عمل مرئي',c.id,c.title,count(v.viewer_id)::bigint
    from public.site_content c
    left join public.content_views v on v.content_type='film' and v.content_id=c.id
    where c.content_type='films' and c.published=true and nullif(c.content_url,'') is not null
    group by c.id,c.title
    union all
    select 'scenario','سيناريو',s.id,s.title,count(v.viewer_id)::bigint
    from public.scenario_scripts s
    left join public.content_views v on v.content_type='scenario' and v.content_id=s.id
    where s.published=true and s.rights_confirmed=true
      and s.rights_status<>'unverified' and nullif(s.rights_holder,'') is not null
    group by s.id,s.title
    union all
    select 'director_video','فيديو مخرج',d.id,d.title,count(v.viewer_id)::bigint
    from public.director_work_submissions d
    left join public.content_views v on v.content_type='director_video' and v.content_id=d.id
    where d.status='approved'
      and (nullif(d.storage_path,'') is not null or nullif(d.external_url,'') is not null)
    group by d.id,d.title
    union all
    select 'archive','أفيش أرشيف',c.id,c.title,count(v.viewer_id)::bigint
    from public.site_content c
    left join public.content_views v on v.content_type='archive' and v.content_id=c.id
    where c.content_type='archive' and c.published=true and nullif(c.image_url,'') is not null
    group by c.id,c.title
  ) content_rows;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_platform_growth_stats()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
declare result jsonb;
begin
  if auth.uid() is null
     or coalesce(auth.jwt()->'app_metadata'->>'role','') <> 'admin'
     or not exists (select 1 from public.admin_users where user_id = (select auth.uid())) then
    raise exception 'admin access required' using errcode='42501';
  end if;

  select jsonb_build_object(
    'total_members', (select count(*) from auth.users u where coalesce(u.raw_app_meta_data->>'role','') <> 'admin'),
    'new_members_7d', (select count(*) from auth.users u where coalesce(u.raw_app_meta_data->>'role','') <> 'admin' and u.created_at >= now() - interval '7 days'),
    'new_members_30d', (select count(*) from auth.users u where coalesce(u.raw_app_meta_data->>'role','') <> 'admin' and u.created_at >= now() - interval '30 days'),
    'active_members_30d', (select count(*) from auth.users u where coalesce(u.raw_app_meta_data->>'role','') <> 'admin' and u.last_sign_in_at >= now() - interval '30 days'),
    'profile_count', (select count(*) from public.member_profiles mp join auth.users u on u.id=mp.user_id where coalesce(u.raw_app_meta_data->>'role','') <> 'admin'),
    'topics_total', (select count(*) from public.community_topics where status='approved'),
    'replies_total', (select count(*) from public.topic_replies where status='approved'),
    'comments_total', (select count(*) from public.content_comments where status='approved'),
    'submissions_total', (select count(*) from public.community_submissions where status='approved'),
    'interactions_total',
      (select count(*) from public.community_topics where status='approved')
      + (select count(*) from public.topic_replies where status='approved')
      + (select count(*) from public.content_comments where status='approved')
      + (select count(*) from public.community_submissions where status='approved'),
    'visits_total', (select count(*) from public.page_visits),
    'unique_visitors', (select count(distinct visitor_id) from public.page_visits where nullif(visitor_id,'') is not null),
    'visits_30d', (select count(*) from public.page_visits where created_at >= now() - interval '30 days'),
    'top_pages', (
      select coalesce(jsonb_agg(jsonb_build_object('page_path',page_path,'visits',visit_count) order by visit_count desc,page_path),'[]'::jsonb)
      from (
        select coalesce(nullif(page_path,''),'/') as page_path,count(*) as visit_count
        from public.page_visits
        group by coalesce(nullif(page_path,''),'/')
        order by count(*) desc,coalesce(nullif(page_path,''),'/')
        limit 6
      ) popular_pages
    )
  ) into result;
  return result;
end;
$function$;
