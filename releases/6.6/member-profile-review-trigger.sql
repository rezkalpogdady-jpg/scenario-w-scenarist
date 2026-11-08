-- سيناريو وسيناريست | 6.6 | إعادة ملف العضو للمراجعة بعد تعديل بياناته
-- Migration مستقل وإضافي. لا يُشغّل قبل مراجعة المخطط الفعلي والنسخة الاحتياطية.
-- لا يحذف بيانات أو جداول أو سياسات. لم يُنفذ على Supabase ضمن هذه المهمة.

begin;

create or replace function public.member_profile_mark_pending_on_owner_update()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $function$
begin
  -- لا نعيد قرار الإدارة إلى pending عند تنفيذ تعديل إداري موثوق.
  -- user_metadata غير مستخدم هنا لأنه قابل للتعديل من صاحب الحساب.
  if auth.uid() = old.user_id
     and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin'
     and (
       new.display_name is distinct from old.display_name
       or new.account_type is distinct from old.account_type
       or new.bio is distinct from old.bio
       or new.city is distinct from old.city
       or new.specialty is distinct from old.specialty
       or new.image_url is distinct from old.image_url
       or new.work_url is distinct from old.work_url
     )
  then
    new.profile_status := 'pending';
    new.updated_at := now();
  end if;

  return new;
end;
$function$;

revoke all on function public.member_profile_mark_pending_on_owner_update() from public, anon, authenticated;

drop trigger if exists member_profile_owner_changes_require_review on public.member_profiles;
create trigger member_profile_owner_changes_require_review
before update of display_name, account_type, bio, city, specialty, image_url, work_url
on public.member_profiles
for each row
execute function public.member_profile_mark_pending_on_owner_update();

comment on function public.member_profile_mark_pending_on_owner_update()
is 'Resets a member-owned profile to pending after a material owner edit; trusted admin edits retain their review decision.';

commit;

-- اختبار قبول مطلوب بعد التنفيذ على بيئة تجريبية:
-- 1) عضو يغيّر bio في ملف approved => profile_status يصبح pending.
-- 2) عضو يحاول إرسال profile_status=approved => مرفوض بامتيازات الأعمدة/RLS.
-- 3) مدير موثوق يراجع الملف ويعتمده، ولا يعيده trigger إلى pending.
-- 4) تحديث لا يغيّر أي حقل من حقول الملف لا يبدّل حالة الاعتماد.
