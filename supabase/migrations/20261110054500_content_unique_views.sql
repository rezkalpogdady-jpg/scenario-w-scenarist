-- 6.8.53: قياس المشاهدات الفريدة لكل محتوى منشور.
create table if not exists public.content_views (
  content_type text not null,
  content_id uuid not null,
  viewer_id uuid not null,
  viewed_at timestamptz not null default now(),
  constraint content_views_pkey primary key (content_type, content_id, viewer_id),
  constraint content_views_type_check check (content_type in ('academy','film','scenario','director_video'))
);
create index if not exists content_views_content_idx
  on public.content_views (content_type, content_id);

alter table public.content_views enable row level security;
revoke all on public.content_views from anon, authenticated, public;

create policy "Public can record valid published content views"
on public.content_views
for insert
to anon, authenticated
with check (
  viewer_id is not null
  and (
    (content_type='academy' and exists (select 1 from public.site_content c where c.id=content_views.content_id and c.content_type='academy' and c.published=true))
    or
    (content_type='film' and exists (select 1 from public.site_content c where c.id=content_views.content_id and c.content_type='films' and c.published=true and nullif(c.content_url,'') is not null))
    or
    (content_type='scenario' and exists (select 1 from public.scenario_scripts s where s.id=content_views.content_id and s.published=true and s.rights_confirmed=true and s.rights_status <> 'unverified' and nullif(s.rights_holder,'') is not null))
    or
    (content_type='director_video' and exists (select 1 from public.director_work_submissions d where d.id=content_views.content_id and d.status='approved' and (nullif(d.storage_path,'') is not null or nullif(d.external_url,'') is not null)))
  )
);
grant insert on public.content_views to anon, authenticated;

create or replace function public.record_public_content_view(
  p_content_type text,
  p_content_id text,
  p_viewer_id text
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $function$
declare target_id uuid; viewer_uuid uuid;
begin
  if p_content_type not in ('academy','film','scenario','director_video')
     or p_content_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}

create or replace function public.admin_content_view_stats()
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

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'content_type', content_type,
      'content_label', content_label,
      'content_id', content_id,
      'title', title,
      'unique_views', unique_views
    ) order by unique_views desc, title
  ), '[]'::jsonb)
  into result
  from (
    select 'academy'::text as content_type, 'محاضرة'::text as content_label,
      c.id as content_id, c.title, count(v.viewer_id)::bigint as unique_views
    from public.site_content c
    left join public.content_views v on v.content_type='academy' and v.content_id=c.id
    where c.content_type='academy' and c.published=true
    group by c.id,c.title
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
    where s.published=true and s.rights_confirmed=true and s.rights_status <> 'unverified' and nullif(s.rights_holder,'') is not null
    group by s.id,s.title
    union all
    select 'director_video','فيديو مخرج',d.id,d.title,count(v.viewer_id)::bigint
    from public.director_work_submissions d
    left join public.content_views v on v.content_type='director_video' and v.content_id=d.id
    where d.status='approved' and (nullif(d.storage_path,'') is not null or nullif(d.external_url,'') is not null)
    group by d.id,d.title
  ) content_rows;

  return result;
end;
$function$;
revoke all on function public.admin_content_view_stats() from public;
revoke all on function public.admin_content_view_stats() from anon;
grant execute on function public.admin_content_view_stats() to authenticated;

     or p_viewer_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}

create or replace function public.admin_content_view_stats()
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

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'content_type', content_type,
      'content_label', content_label,
      'content_id', content_id,
      'title', title,
      'unique_views', unique_views
    ) order by unique_views desc, title
  ), '[]'::jsonb)
  into result
  from (
    select 'academy'::text as content_type, 'محاضرة'::text as content_label,
      c.id as content_id, c.title, count(v.viewer_id)::bigint as unique_views
    from public.site_content c
    left join public.content_views v on v.content_type='academy' and v.content_id=c.id
    where c.content_type='academy' and c.published=true
    group by c.id,c.title
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
    where s.published=true and s.rights_confirmed=true and s.rights_status <> 'unverified' and nullif(s.rights_holder,'') is not null
    group by s.id,s.title
    union all
    select 'director_video','فيديو مخرج',d.id,d.title,count(v.viewer_id)::bigint
    from public.director_work_submissions d
    left join public.content_views v on v.content_type='director_video' and v.content_id=d.id
    where d.status='approved' and (nullif(d.storage_path,'') is not null or nullif(d.external_url,'') is not null)
    group by d.id,d.title
  ) content_rows;

  return result;
end;
$function$;
revoke all on function public.admin_content_view_stats() from public;
revoke all on function public.admin_content_view_stats() from anon;
grant execute on function public.admin_content_view_stats() to authenticated;
 then
    return false;
  end if;
  target_id := p_content_id::uuid;
  viewer_uuid := p_viewer_id::uuid;
  insert into public.content_views(content_type,content_id,viewer_id)
  values(p_content_type,target_id,viewer_uuid)
  on conflict (content_type,content_id,viewer_id) do nothing;
  return true;
end;
$function$;
revoke all on function public.record_public_content_view(text,text,text) from public;
grant execute on function public.record_public_content_view(text,text,text) to anon, authenticated;

create or replace function public.admin_content_view_stats()
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

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'content_type', content_type,
      'content_label', content_label,
      'content_id', content_id,
      'title', title,
      'unique_views', unique_views
    ) order by unique_views desc, title
  ), '[]'::jsonb)
  into result
  from (
    select 'academy'::text as content_type, 'محاضرة'::text as content_label,
      c.id as content_id, c.title, count(v.viewer_id)::bigint as unique_views
    from public.site_content c
    left join public.content_views v on v.content_type='academy' and v.content_id=c.id
    where c.content_type='academy' and c.published=true
    group by c.id,c.title
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
    where s.published=true and s.rights_confirmed=true and s.rights_status <> 'unverified' and nullif(s.rights_holder,'') is not null
    group by s.id,s.title
    union all
    select 'director_video','فيديو مخرج',d.id,d.title,count(v.viewer_id)::bigint
    from public.director_work_submissions d
    left join public.content_views v on v.content_type='director_video' and v.content_id=d.id
    where d.status='approved' and (nullif(d.storage_path,'') is not null or nullif(d.external_url,'') is not null)
    group by d.id,d.title
  ) content_rows;

  return result;
end;
$function$;
revoke all on function public.admin_content_view_stats() from public;
revoke all on function public.admin_content_view_stats() from anon;
grant execute on function public.admin_content_view_stats() to authenticated;
