-- سيناريو وسيناريست | فحص متطلبات Migration 6.5 قبل تشغيلها
-- READ ONLY بالكامل: يعرض الموجود والناقص دون إيقاف الاستعلام أو تعديل أي شيء.
-- مهم: سبق أن ظهر الخطأ 42P01 لعدم وجود public.member_profiles.
-- شغّل هذا الملف أولًا في Supabase SQL Editor، ولا تشغّل Migration 6.5
-- إذا ظهرت أي قيمة MISSING في النتائج.

-- 1) الجداول التي تعتمد عليها Migration 6.5.
with required(table_name) as (
  values
    ('member_profiles'),
    ('member_works')
)
select r.table_name,
       case when c.oid is null then 'MISSING' else 'PRESENT' end as status,
       coalesce(c.relrowsecurity,false) as rls_enabled,
       coalesce(c.relforcerowsecurity,false) as force_rls
from required r
left join pg_namespace n on n.nspname='public'
left join pg_class c on c.relnamespace=n.oid
                    and c.relname=r.table_name
                    and c.relkind in ('r','p')
order by r.table_name;

-- 2) الأعمدة التي تستخدمها Migration 6.5 مباشرة.
with required(table_name,column_name) as (
  values
    ('member_profiles','user_id'),
    ('member_profiles','profile_status'),
    ('member_profiles','display_name'),
    ('member_profiles','account_type'),
    ('member_profiles','bio'),
    ('member_profiles','city'),
    ('member_profiles','specialty'),
    ('member_profiles','image_url'),
    ('member_profiles','work_url'),
    ('member_profiles','updated_at'),
    ('member_profiles','reviewed_at'),
    ('member_works','id'),
    ('member_works','user_id'),
    ('member_works','status'),
    ('member_works','storage_path')
)
select r.table_name,r.column_name,
       case when c.column_name is null then 'MISSING' else 'PRESENT' end as status,
       c.data_type,c.column_default
from required r
left join information_schema.columns c
  on c.table_schema='public'
 and c.table_name=r.table_name
 and c.column_name=r.column_name
order by r.table_name,r.column_name;

-- 3) مكونات Supabase Storage التي تعتمد عليها Migration 6.5.
select 'storage.buckets' as object_name,
       case when to_regclass('storage.buckets') is null then 'MISSING' else 'PRESENT' end as status
union all
select 'storage.objects',
       case when to_regclass('storage.objects') is null then 'MISSING' else 'PRESENT' end
union all
select 'storage.foldername(text)',
       case when to_regprocedure('storage.foldername(text)') is null then 'MISSING' else 'PRESENT' end;

-- 4) مساحة التخزين المطلوبة.
select 'member-submissions' as bucket_id,
       case when to_regclass('storage.buckets') is null then 'CANNOT_CHECK'
            when exists(select 1 from storage.buckets where id='member-submissions') then 'PRESENT'
            else 'MISSING' end as status;

-- لا توجد أوامر CREATE / ALTER / DROP / GRANT / REVOKE / DML في هذا الملف.
-- وجود كل المتطلبات لا يثبت صحة السياسات؛ استخدم كذلك preflight-6.5-readonly.sql
-- وراجع نتائجه قبل أي تنفيذ، ولا تشغّل Migration إلا بعد مراجعة النتائج والموافقة.
