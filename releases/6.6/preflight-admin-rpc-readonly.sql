-- سيناريو وسيناريست | 6.6 | فحص دوال مراجعة الإدارة
-- READ ONLY: لا ينفذ أي CREATE/ALTER/GRANT/REVOKE أو تعديل بيانات.
-- شغّله في Supabase SQL Editor بحساب يملك قراءة كتالوج PostgreSQL.
-- لا تشارك نتائج تعريف الدوال علنًا إذا كانت تحتوي أي بيانات حساسة أضيفت بالخطأ.

-- 1) هل الدوال الثلاث موجودة؟ وما توقيعها ومالكها ولغة التنفيذ؟
select n.nspname as schema_name,
       p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as identity_arguments,
       pg_get_userbyid(p.proowner) as function_owner,
       l.lanname as language,
       p.prosecdef as security_definer,
       p.proconfig as function_settings,
       p.proacl as function_acl,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_can_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
join pg_language l on l.oid=p.prolang
where n.nspname='public'
  and p.proname in (
    'admin_review_member_profile',
    'admin_review_member_work',
    'admin_review_community_submission'
  )
order by p.proname,identity_arguments;

-- 2) تعريفات الدوال لمراجعتها يدويًا:
-- تحقق من auth.uid()/مطالبة app_metadata الموثوقة، والتحقق من status،
-- وربط السجل بالمفتاح الصحيح، وعدم قبول owner_id أو حقول قرار المراجعة من العميل.
-- راجع كل استعلام UPDATE/INSERT وأي تعامل مع Storage أو روابط النشر.
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as identity_arguments,
       pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'admin_review_member_profile',
    'admin_review_member_work',
    'admin_review_community_submission'
  )
order by p.proname,identity_arguments;

-- 3) إظهار إعدادات search_path المعرّفة على الدوال بشكل واضح.
-- يجب تثبيت search_path داخل SECURITY DEFINER وعدم الاعتماد على إعداد جلسة العميل.
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as identity_arguments,
       coalesce(array_to_string(p.proconfig,', '),'(not pinned)') as function_settings
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'admin_review_member_profile',
    'admin_review_member_work',
    'admin_review_community_submission'
  )
order by p.proname,identity_arguments;

-- 4) لا تعتبر وجود SECURITY DEFINER حماية بحد ذاته.
-- يجب أن تكون الدوال محمية داخليًا، وألا يستطيع anon تنفيذها.
-- authenticated قد يحتاج EXECUTE لاستدعاء RPC من لوحة المدير، لذلك يلزم
-- فحص الدور داخل الدالة نفسها؛ لا يكفي حجب زر الواجهة.
