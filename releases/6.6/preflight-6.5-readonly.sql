-- سيناريو وسيناريست | فحص ما قبل Migration 6.5 ومراجعة صلاحيات المنصة
-- READ ONLY: لا ينشئ أو يعدل أو يحذف أي جدول أو سياسة أو ملف أو صلاحية.
-- شغّله في Supabase SQL Editor بحساب مالك المشروع.
-- أي EXCEPTION يعني التوقف وعدم تشغيل Migration 6.5 حتى معالجة السبب.

do $preflight$
declare
  missing text[] := array[]::text[];
  required_table text;
  required_column text;
  missing_tables text[] := array[]::text[];
  rls_disabled text[] := array[]::text[];
  bucket_missing text[] := array[]::text[];
  required_tables text[] := array[
    'site_content','scenario_scripts','idea_submissions',
    'community_submissions','community_topics','topic_replies',
    'content_comments','content_ratings','member_profiles',
    'member_works','chess_games','page_visits'
  ];
  required_buckets text[] := array['site-media','member-submissions'];
  required_functions text[] := array[
    'admin_review_member_work','admin_review_member_profile',
    'admin_review_community_submission','admin_visit_stats',
    'join_chess_game','submit_chess_position'
  ];
  fn text;
begin
  -- كل الجداول التي يستدعيها كود الواجهة مباشرة.
  foreach required_table in array required_tables loop
    if to_regclass('public.'||quote_ident(required_table)) is null then
      missing_tables := array_append(missing_tables, 'public.'||required_table);
    elsif not exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=required_table
        and c.relrowsecurity
    ) then
      rls_disabled := array_append(rls_disabled, 'public.'||required_table);
    end if;
  end loop;

  if coalesce(array_length(missing_tables,1),0)>0 then
    raise exception 'Preflight failed: missing application tables: %', array_to_string(missing_tables, ', ');
  end if;
  if coalesce(array_length(rls_disabled,1),0)>0 then
    raise exception 'Preflight failed: RLS is not enabled on: %', array_to_string(rls_disabled, ', ');
  end if;

  -- أعمدة الحد الأدنى التي يعتمد عليها تحديث 6.5 ومسارات الحسابات.
  for required_table, required_column in
    select * from (values
      ('member_profiles','user_id'),
      ('member_profiles','display_name'),
      ('member_profiles','account_type'),
      ('member_profiles','profile_status'),
      ('member_profiles','updated_at'),
      ('member_works','id'),
      ('member_works','user_id'),
      ('member_works','title'),
      ('member_works','status'),
      ('member_works','storage_path'),
      ('site_content','id'),
      ('site_content','title'),
      ('site_content','content_type'),
      ('site_content','published'),
      ('site_content','created_at')
    ) as required(table_name,column_name)
  loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public'
        and table_name=required_table
        and column_name=required_column
    ) then
      missing := array_append(missing,'public.'||required_table||'.'||required_column);
    end if;
  end loop;
  if coalesce(array_length(missing,1),0)>0 then
    raise exception 'Preflight failed: missing required columns: %',array_to_string(missing,', ');
  end if;

  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise exception 'Preflight failed: Supabase Storage catalog is unavailable.';
  end if;

  foreach required_table in array required_buckets loop
    if not exists(select 1 from storage.buckets where id=required_table) then
      bucket_missing := array_append(bucket_missing,required_table);
    end if;
  end loop;
  if coalesce(array_length(bucket_missing,1),0)>0 then
    raise exception 'Preflight failed: required Storage buckets are missing: %',array_to_string(bucket_missing,', ');
  end if;

  foreach fn in array required_functions loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=fn
    ) then
      raise notice 'Required/expected RPC not found: public.% (confirm whether this feature is enabled)',fn;
    end if;
  end loop;

  raise notice 'Preflight passed: required tables, RLS flags, minimum columns and Storage buckets exist.';
  raise notice 'This does not certify policy correctness, function safety, or runtime behavior. Review all result sets below.';
end
$preflight$;

-- 1) كل سياسات RLS للجداول التي يستعملها التطبيق، بما فيها الصلاحيات الممنوحة فعليًا.
select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
from pg_policies
where schemaname='public'
  and tablename in (
    'site_content','scenario_scripts','idea_submissions',
    'community_submissions','community_topics','topic_replies',
    'content_comments','content_ratings','member_profiles',
    'member_works','chess_games','page_visits'
  )
order by tablename,cmd,policyname;

-- 2) حالة RLS و FORCE RLS لكل جدول من جداول التطبيق.
select n.nspname as schema_name,c.relname as table_name,
       c.relrowsecurity as rls_enabled,c.relforcerowsecurity as force_rls
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public'
  and c.relkind in ('r','p')
  and c.relname in (
    'site_content','scenario_scripts','idea_submissions',
    'community_submissions','community_topics','topic_replies',
    'content_comments','content_ratings','member_profiles',
    'member_works','chess_games','page_visits'
  )
order by c.relname;

-- 3) امتيازات الجداول والأعمدة للأدوار anon/authenticated/PUBLIC.
-- راجع خصوصًا أي امتياز واسع ممنوح إلى PUBLIC.
select table_schema,table_name,grantee,privilege_type
from information_schema.role_table_grants
where table_schema='public'
  and table_name in (
    'site_content','scenario_scripts','idea_submissions',
    'community_submissions','community_topics','topic_replies',
    'content_comments','content_ratings','member_profiles',
    'member_works','chess_games','page_visits'
  )
  and grantee in ('anon','authenticated','PUBLIC')
order by table_name,grantee,privilege_type;

-- 4) خصائص التخزين وسياسات الوصول إلى storage.objects.
select id,name,public,file_size_limit,allowed_mime_types
from storage.buckets
where id in ('site-media','member-submissions')
order by id;

select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
from pg_policies
where schemaname='storage' and tablename='objects'
order by policyname;

-- 5) تعريفات دوال الإدارة وأمن التنفيذ. لا نعرض أجسام الدوال أو أسرارًا.
select n.nspname as schema_name,p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.prosecdef as security_definer,
       p.proconfig as function_settings,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_can_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'admin_review_member_work','admin_review_member_profile',
    'admin_review_community_submission','admin_visit_stats',
    'join_chess_game','submit_chess_position'
  )
order by p.proname;


-- 7) فحص القيمة الافتراضية الفعلية لحالة ملف العضو وامتيازات الأعمدة.
-- نموذج التسجيل لا يرسل profile_status؛ لذلك يجب أن يكون default في الجدول pending.
-- كما يجب ألا يستطيع authenticated تحديث profile_status مباشرة.
select table_name,column_name,data_type,udt_name,column_default,is_nullable
from information_schema.columns
where table_schema='public'
  and table_name='member_profiles'
  and column_name in ('profile_status','reviewed_at','updated_at')
order by ordinal_position;

select
  has_table_privilege('authenticated','public.member_profiles','UPDATE') as authenticated_table_update,
  has_column_privilege('authenticated','public.member_profiles','profile_status','UPDATE') as authenticated_can_update_profile_status,
  has_column_privilege('authenticated','public.member_profiles','reviewed_at','UPDATE') as authenticated_can_update_reviewed_at,
  has_column_privilege('authenticated','public.member_profiles','display_name','UPDATE') as authenticated_can_update_display_name,
  has_column_privilege('authenticated','public.member_profiles','bio','UPDATE') as authenticated_can_update_bio;

-- راجع نتيجة profile_status يدويًا:
-- المتوقع: column_default يعيد 'pending' (أو تعبيرًا مكافئًا)،
-- و authenticated_can_update_profile_status = false.
-- هذا الفحص للقراءة فقط ولا يغير أي امتياز أو قيمة افتراضية.


-- 8) فحص القيمة الافتراضية وحماية أعمدة أعمال الأعضاء.
-- insert في الواجهة لا يرسل status؛ لذلك يجب أن يكون default = pending.
select table_name,column_name,data_type,column_default,is_nullable
from information_schema.columns
where table_schema='public'
  and table_name='member_works'
  and column_name in ('status','created_at')
order by ordinal_position;

select
  has_table_privilege('authenticated','public.member_works','UPDATE') as authenticated_table_update,
  has_table_privilege('authenticated','public.member_works','DELETE') as authenticated_table_delete,
  has_table_privilege('authenticated','public.member_works','INSERT') as authenticated_table_insert,
  has_column_privilege('authenticated','public.member_works','status','UPDATE') as authenticated_can_update_status,
  has_column_privilege('authenticated','public.member_works','user_id','UPDATE') as authenticated_can_update_owner,
  has_column_privilege('authenticated','public.member_works','storage_path','UPDATE') as authenticated_can_update_storage_path;

-- 9) تعريف دالة مراجعة أعمال الأعضاء وصلاحيات تنفيذها.
-- يجب أن تكون محمية داخل جسم الدالة وتتحقق من app_metadata.role = admin.
select
  p.oid::regprocedure as function_signature,
  pg_get_userbyid(p.proowner) as function_owner,
  p.prosecdef as security_definer,
  p.proconfig as function_settings,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute,
  pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='admin_review_member_work';

-- 6) تعريف دالة اعتماد ملف العضو: تحقق يدوي من التفويض داخل جسم الدالة.
-- يجب أن تتحقق الدالة من app_metadata.role = admin (أو آلية موثوقة مكافئة)،
-- وألا تعتمد على user_metadata أو قيمة يرسلها العميل.
select
  p.oid::regprocedure as function_signature,
  pg_get_userbyid(p.proowner) as function_owner,
  p.prosecdef as security_definer,
  p.proconfig as function_settings,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute,
  pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='admin_review_member_profile';

-- 6) عرض triggers على ملفات الأعضاء؛ مهمة لمعرفة هل تحديث الملف يعيد الحالة pending.
select event_object_table as table_name,trigger_name,event_manipulation,
       action_timing,action_statement
from information_schema.triggers
where trigger_schema='public'
  and event_object_table in ('member_profiles','member_works')
order by event_object_table,trigger_name,event_manipulation;


-- 10) مكتبة السيناريوهات الكاملة: تحقق قراءة فقط من مساحة PDF الخاصة.
-- المتوقع: scenario-scripts موجودة و public=false وحد الرفع مناسب (حتى 50 MiB).
-- يجب أن تسمح سياسات القراءة للأعضاء المسجلين بإنشاء Signed URL فقط،
-- دون منح anon وصولًا مباشرًا إلى ملفات المكتبة.
select id,name,public,file_size_limit,allowed_mime_types
from storage.buckets
where id='scenario-scripts';

select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
from pg_policies
where schemaname='storage' and tablename='objects'
order by policyname;

-- فحص امتيازات سجل المكتبة. الواجهة العامة تقرأ بيانات منشورة فقط،
-- والملفات نفسها لا تُقرأ إلا عبر Signed URL بعد التحقق من تسجيل الدخول.
select
  has_table_privilege('anon',(select to_regclass('public.scenario_scripts')),'SELECT') as anon_can_select_metadata,
  has_table_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'SELECT') as authenticated_can_select_metadata,
  has_table_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'INSERT') as authenticated_can_insert,
  has_table_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'UPDATE') as authenticated_can_update,
  has_table_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'DELETE') as authenticated_can_delete;

-- ملاحظة: هذه الاستعلامات لا تغيّر أي إعداد. لا تعتبر bucket آمنًا
-- قبل مراجعة public=false والسياسات الفعلية ونتائج الوصول بحساب anon وعضو ومدير.


-- 11) وجود جدول مكتبة السيناريوهات وتفعيل RLS عليه.
-- يعرض صفًا واحدًا حتى لو لم يوجد الجدول، لتسهيل اكتشاف غياب الإعداد.
select
  to_regclass('public.scenario_scripts') as scenario_scripts_table,
  coalesce(c.relrowsecurity,false) as rls_enabled,
  coalesce(c.relforcerowsecurity,false) as rls_forced
from (select 1) seed
left join pg_class c on c.oid=to_regclass('public.scenario_scripts');

-- 12) جميع سياسات RLS الخاصة بجدول السيناريوهات، إن وُجدت.
select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
from pg_policies
where schemaname='public' and tablename='scenario_scripts'
order by policyname;

-- 13) صلاحيات الأدوار على جدول المكتبة.
-- راجعها مع السياسات: anon يجب ألا يستطيع الكتابة أو قراءة storage_path،
-- والأعضاء لا يملكون إدارة السجلات أو تغيير حالة النشر.
select
  has_table_privilege('anon',(select to_regclass('public.scenario_scripts')),'SELECT') as anon_can_select_metadata,
  has_table_privilege('anon',(select to_regclass('public.scenario_scripts')),'INSERT') as anon_can_insert,
  has_table_privilege('anon',(select to_regclass('public.scenario_scripts')),'UPDATE') as anon_can_update,
  has_table_privilege('anon',(select to_regclass('public.scenario_scripts')),'DELETE') as anon_can_delete,
  has_table_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'SELECT') as authenticated_can_select,
  has_table_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'INSERT') as authenticated_can_insert,
  has_table_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'UPDATE') as authenticated_can_update,
  has_table_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'DELETE') as authenticated_can_delete;

-- 14) امتيازات الأعمدة الحساسة: مسار التخزين وحالة النشر.
select
  has_column_privilege('anon',(select to_regclass('public.scenario_scripts')),'storage_path','SELECT') as anon_can_read_storage_path,
  has_column_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'storage_path','SELECT') as authenticated_can_read_storage_path,
  has_column_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'published','UPDATE') as authenticated_can_update_published,
  has_column_privilege('authenticated',(select to_regclass('public.scenario_scripts')),'storage_path','UPDATE') as authenticated_can_update_storage_path;
