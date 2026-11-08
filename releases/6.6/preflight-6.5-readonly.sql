-- سيناريو وسيناريست | فحص ما قبل Migration 6.5
-- READ ONLY: هذا الملف لا ينشئ أو يعدل أو يحذف أي جدول أو سياسة أو ملف.
-- شغّله أولًا في Supabase SQL Editor بحساب مالك المشروع.
-- إذا ظهر EXCEPTION فتوقف ولا تشغّل migration.sql قبل معالجة السبب.

do $preflight$
declare
  missing text[] := array[]::text[];
  tbl text;
  col text;
  has_admin_review boolean;
  has_site_media boolean;
  has_member_submissions boolean;
  permissive_count integer;
begin
  -- الجداول والأعمدة التي يعتمد عليها كود المنصة وMigration 6.5.
  for tbl, col in
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
      select 1
        from information_schema.columns
       where table_schema='public'
         and table_name=tbl
         and column_name=col
    ) then
      missing := array_append(missing, 'public.'||tbl||'.'||col);
    end if;
  end loop;

  if coalesce(array_length(missing,1),0) > 0 then
    raise exception 'Preflight failed. Missing required columns: %', array_to_string(missing, ', ');
  end if;

  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise exception 'Preflight failed. Supabase Storage tables are unavailable.';
  end if;

  select exists(select 1 from storage.buckets where id='site-media') into has_site_media;
  select exists(select 1 from storage.buckets where id='member-submissions') into has_member_submissions;

  if not has_site_media then
    raise exception 'Preflight failed. Required bucket site-media does not exist.';
  end if;
  if not has_member_submissions then
    raise exception 'Preflight failed. Required bucket member-submissions does not exist.';
  end if;

  select exists(
    select 1 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='admin_review_member_work'
  ) into has_admin_review;

  if not has_admin_review then
    raise exception 'Preflight failed. RPC public.admin_review_member_work is missing.';
  end if;

  -- Restrictive policies do not grant access by themselves.
  -- At least one permissive policy must also allow each intended operation.
  select count(*) into permissive_count
    from pg_policies
   where schemaname='public'
     and tablename='member_profiles'
     and permissive='PERMISSIVE'
     and 'authenticated'=any(roles);

  raise notice 'member_profiles permissive policies for authenticated: %', permissive_count;

  select count(*) into permissive_count
    from pg_policies
   where schemaname='public'
     and tablename='member_works'
     and permissive='PERMISSIVE'
     and 'authenticated'=any(roles);

  raise notice 'member_works permissive policies for authenticated: %', permissive_count;

  select count(*) into permissive_count
    from pg_policies
   where schemaname='storage'
     and tablename='objects'
     and permissive='PERMISSIVE'
     and 'authenticated'=any(roles);

  raise notice 'storage.objects permissive policies for authenticated: %', permissive_count;

  raise notice 'Preflight passed for required schema and buckets. Review permissive policy counts and verify every policy expression before applying migration 6.5.';
end
$preflight$;

-- مراجعة السياسات الحالية بالتفصيل (قراءة فقط):
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
  from pg_policies
 where (schemaname='public' and tablename in ('member_profiles','member_works','site_content'))
    or (schemaname='storage' and tablename='objects')
 order by schemaname, tablename, policyname;

-- مراجعة خصائص التخزين:
select id, name, public, file_size_limit, allowed_mime_types
  from storage.buckets
 where id in ('site-media','member-submissions')
 order by id;

-- مراجعة وجود دوال الإدارة (لا تعرض أجسام الدوال أو أسرارًا):
select n.nspname as schema_name, p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.prosecdef as security_definer
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public'
   and p.proname in (
     'admin_review_member_work',
     'admin_review_member_profile',
     'admin_review_community_submission',
     'admin_visit_stats'
   )
 order by p.proname;
