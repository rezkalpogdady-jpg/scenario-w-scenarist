-- 6.8.72: Track unique views for archive posters and expose them in admin content-view stats.
-- Existing rating/comment records remain untouched.
DROP POLICY IF EXISTS "Public can record valid published content views" ON public.content_views;
CREATE POLICY "Public can record valid published content views" ON public.content_views FOR INSERT TO anon, authenticated WITH CHECK (
  viewer_id IS NOT NULL AND (
    (content_type = 'academy' AND EXISTS (SELECT 1 FROM public.site_content c WHERE c.id=content_views.content_id AND c.content_type='academy' AND c.published=true)) OR
    (content_type = 'film' AND EXISTS (SELECT 1 FROM public.site_content c WHERE c.id=content_views.content_id AND c.content_type='films' AND c.published=true AND NULLIF(c.content_url,'') IS NOT NULL)) OR
    (content_type = 'scenario' AND EXISTS (SELECT 1 FROM public.scenario_scripts s WHERE s.id=content_views.content_id AND s.published=true AND s.rights_confirmed=true AND s.rights_status<>'unverified' AND NULLIF(s.rights_holder,'') IS NOT NULL)) OR
    (content_type = 'director_video' AND EXISTS (SELECT 1 FROM public.director_work_submissions d WHERE d.id=content_views.content_id AND d.status='approved' AND (NULLIF(d.storage_path,'') IS NOT NULL OR NULLIF(d.external_url,'') IS NOT NULL))) OR
    (content_type = 'archive' AND EXISTS (SELECT 1 FROM public.site_content c WHERE c.id=content_views.content_id AND c.content_type='archive' AND c.published=true AND NULLIF(c.image_url,'') IS NOT NULL))
  )
);
CREATE OR REPLACE FUNCTION public.record_public_content_view(p_content_type text,p_content_id text,p_viewer_id text)
RETURNS boolean LANGUAGE plpgsql SET search_path TO '' AS $function$
declare target_id uuid; viewer_uuid uuid;
begin
  if p_content_type is null or p_content_id is null or p_viewer_id is null
     or p_content_type not in ('academy','film','scenario','director_video','archive')
     or p_content_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or p_viewer_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  target_id:=p_content_id::uuid; viewer_uuid:=p_viewer_id::uuid;
  insert into public.content_views(content_type,content_id,viewer_id) values(p_content_type,target_id,viewer_uuid)
  on conflict(content_type,content_id,viewer_id) do nothing;
  return true;
end; $function$;
CREATE OR REPLACE FUNCTION public.admin_content_view_stats()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
declare result jsonb;
begin
  if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'admin access required' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('content_type',content_type,'content_label',content_label,'content_id',content_id,'title',title,'unique_views',unique_views) order by unique_views desc,title),'[]'::jsonb) into result
  from (
    select 'academy'::text content_type,'محاضرة'::text content_label,c.id content_id,c.title,count(v.viewer_id)::bigint unique_views from public.site_content c left join public.content_views v on v.content_type='academy' and v.content_id=c.id where c.content_type='academy' and c.published=true group by c.id,c.title
    union all select 'film','فيديو / عمل مرئي',c.id,c.title,count(v.viewer_id)::bigint from public.site_content c left join public.content_views v on v.content_type='film' and v.content_id=c.id where c.content_type='films' and c.published=true and nullif(c.content_url,'') is not null group by c.id,c.title
    union all select 'scenario','سيناريو',s.id,s.title,count(v.viewer_id)::bigint from public.scenario_scripts s left join public.content_views v on v.content_type='scenario' and v.content_id=s.id where s.published=true and s.rights_confirmed=true and s.rights_status<>'unverified' and nullif(s.rights_holder,'') is not null group by s.id,s.title
    union all select 'director_video','فيديو مخرج',d.id,d.title,count(v.viewer_id)::bigint from public.director_work_submissions d left join public.content_views v on v.content_type='director_video' and v.content_id=d.id where d.status='approved' and (nullif(d.storage_path,'') is not null or nullif(d.external_url,'') is not null) group by d.id,d.title
    union all select 'archive','أفيش أرشيف',c.id,c.title,count(v.viewer_id)::bigint from public.site_content c left join public.content_views v on v.content_type='archive' and v.content_id=c.id where c.content_type='archive' and c.published=true and nullif(c.image_url,'') is not null group by c.id,c.title
  ) content_rows;
  return result;
end; $function$;
