-- سيناريو وسيناريست | 6.8 | فحص وصول الإدارة وبيانات المنصة
-- READ ONLY: لا ينفذ أي CREATE/ALTER/GRANT/REVOKE أو تعديل بيانات.
-- شغّل في Supabase SQL Editor بحساب يملك قراءة كتالوج PostgreSQL.
-- الغرض: إظهار حالة RLS والامتيازات والسياسات الفعلية قبل إعداد أي Migration.
-- لا تعتبر نتائج هذا الفحص بديلًا عن اختبارات الدخول بحساب عضو ومدير.

-- 1) وجود الجداول الأساسية وحالة RLS وامتيازات الأدوار.
with targets(table_name) as (
  values
    ('site_content'),
    ('scenario_scripts'),
    ('idea_submissions'),
    ('community_submissions'),
    ('community_topics'),
    ('topic_replies'),
    ('content_comments'),
    ('content_ratings'),
    ('member_profiles'),
    ('member_works'),
    ('chess_games'),
    ('page_visits')
)
select t.table_name,
       c.oid is not null as table_exists,
       coalesce(c.relrowsecurity,false) as rls_enabled,
       coalesce(c.relforcerowsecurity,false) as force_rls,
       case when c.oid is not null then pg_get_userbyid(c.relowner) end as table_owner,
       case when c.oid is not null then has_table_privilege('anon',c.oid,'SELECT') end as anon_select,
       case when c.oid is not null then has_table_privilege('anon',c.oid,'INSERT') end as anon_insert,
       case when c.oid is not null then has_table_privilege('anon',c.oid,'UPDATE') end as anon_update,
       case when c.oid is not null then has_table_privilege('anon',c.oid,'DELETE') end as anon_delete,
       case when c.oid is not null then has_table_privilege('authenticated',c.oid,'SELECT') end as authenticated_select,
       case when c.oid is not null then has_table_privilege('authenticated',c.oid,'INSERT') end as authenticated_insert,
       case when c.oid is not null then has_table_privilege('authenticated',c.oid,'UPDATE') end as authenticated_update,
       case when c.oid is not null then has_table_privilege('authenticated',c.oid,'DELETE') end as authenticated_delete
from targets t
left join pg_namespace n on n.nspname='public'
left join pg_class c on c.relnamespace=n.oid and c.relname=t.table_name and c.relkind in ('r','p')
order by t.table_name;

-- 2) كل سياسات RLS للجداول المستهدفة؛ راجع permissive/restrictive
-- وUSING وWITH CHECK معًا. السياسات permissive تتحد بـ OR والتقييدية بـ AND.
select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
from pg_policies
where schemaname='public'
  and tablename in (
    'site_content','scenario_scripts','idea_submissions','community_submissions',
    'community_topics','topic_replies','content_comments','content_ratings',
    'member_profiles','member_works','chess_games','page_visits'
  )
order by tablename,cmd,policyname;

-- 3) سياسات التخزين الحالية، دون افتراض أن اسم bucket مذكور في نص السياسة.
select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
from pg_policies
where schemaname='storage' and tablename='objects'
order by cmd,policyname;

-- 4) إعدادات مساحات الملفات المستخدمة في المنصة.
select id,name,public,file_size_limit,allowed_mime_types
from storage.buckets
where id in ('site-media','scenario-scripts','member-submissions')
order by id;

-- 5) الدوال التي تستدعيها الواجهة في مسارات الإدارة/الشطرنج.
-- وجود الدالة لا يثبت سلامتها؛ راجع التعريف وSECURITY DEFINER وsearch_path
-- وفحص دور المدير داخل جسم الدالة، وامتيازات EXECUTE الفعلية.
select n.nspname as schema_name,
       p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as identity_arguments,
       pg_get_userbyid(p.proowner) as function_owner,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig,', '),'(not pinned)') as function_settings,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_can_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute,
       pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'admin_review_member_profile',
    'admin_review_member_work',
    'admin_review_community_submission',
    'admin_visit_stats',
    'join_chess_game',
    'submit_chess_position'
  )
order by p.proname,identity_arguments;

-- 6) Triggers على الجداول التي تعتمد على مراجعة أو تحديثات حساسة.
select n.nspname as schema_name,
       c.relname as table_name,
       tg.tgname as trigger_name,
       pg_get_triggerdef(tg.oid,true) as trigger_definition,
       pg_get_userbyid(p.proowner) as function_owner,
       p.prosecdef as function_security_definer
from pg_trigger tg
join pg_class c on c.oid=tg.tgrelid
join pg_namespace n on n.oid=c.relnamespace
join pg_proc p on p.oid=tg.tgfoid
where not tg.tgisinternal
  and n.nspname='public'
  and c.relname in (
    'site_content','scenario_scripts','idea_submissions','community_submissions',
    'community_topics','topic_replies','content_comments','content_ratings',
    'member_profiles','member_works','chess_games','page_visits'
  )
order by c.relname,tg.tgname;

-- ملاحظات المراجعة:
-- * لا تشغّل أي Migration قبل حفظ نتائج هذا الفحص ومطابقتها مع مخطط المشروع الحي.
-- * لا تمنح authenticated صلاحيات إدارة لمجرد أن زر الإدارة مخفي عن غير المدير.
-- * أي عملية مباشرة من المتصفح يجب أن تكون محكومة بسياسات RLS/Storage دقيقة،
--   أو تُنقل إلى RPC تتحقق من دور المدير داخل قاعدة البيانات.
-- * لا تعتبر app_metadata.role في JavaScript وحده حماية للخادم.
-- * اختبر anon وعضوًا عاديًا ومديرًا، ثم اختبر عضوين مختلفين للتأكد من عزل البيانات.
