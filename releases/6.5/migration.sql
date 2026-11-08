-- سيناريو وسيناريست | المرحلة 06 | تحديث 6.5
-- تقوية صلاحيات ملفات الأعضاء وأعمالهم وملفات الإرسال الخاصة.
-- Migration إضافي تراكمي بعد تحديث 6.4. لا يحذف بيانات أو ملفات أو سجلات.
-- نفّذه مرة واحدة في Supabase SQL Editor بحساب مالك المشروع.

begin;

-- 1) ملف العضو: تأكيد أن العضو لا يرى إلا ملفه أو الملفات المعتمدة،
-- وأن الإدارة المخولة فقط تستطيع الاطلاع على الملفات غير المعتمدة.
drop policy if exists "6.5 restrict member profile reads" on public.member_profiles;
create policy "6.5 restrict member profile reads"
  on public.member_profiles as restrictive for select to authenticated
  using (
    auth.uid() = user_id
    or profile_status = 'approved'
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

drop policy if exists "6.5 restrict member profile inserts" on public.member_profiles;
create policy "6.5 restrict member profile inserts"
  on public.member_profiles as restrictive for insert to authenticated
  with check (auth.uid() = user_id and profile_status = 'pending');

drop policy if exists "6.5 restrict member profile updates" on public.member_profiles;
create policy "6.5 restrict member profile updates"
  on public.member_profiles as restrictive for update to authenticated
  using (
    auth.uid() = user_id
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  )
  with check (
    auth.uid() = user_id
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- إبقاء تحديث بيانات الملف متاحًا عبر الأعمدة المسموح بها فقط.
-- لا يحصل العضو على صلاحية مباشرة لتعديل profile_status أو reviewed_at.
revoke update on public.member_profiles from authenticated;
grant update (display_name, account_type, bio, city, specialty, image_url, work_url, updated_at)
  on public.member_profiles to authenticated;

-- 2) أعمال الأعضاء: القراءة للمالك أو المدير فقط، والإرسال الجديد pending فقط.
drop policy if exists "6.5 restrict member work reads" on public.member_works;
create policy "6.5 restrict member work reads"
  on public.member_works as restrictive for select to authenticated
  using (
    auth.uid() = user_id
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

drop policy if exists "6.5 restrict member work inserts" on public.member_works;
create policy "6.5 restrict member work inserts"
  on public.member_works as restrictive for insert to authenticated
  with check (auth.uid() = user_id and status = 'pending');

-- لا تعديل مباشر لحالة العمل أو صاحبه أو توقيت مراجعته من حساب العضو.
-- الاعتماد والرفض يمران حصريًا عبر دالة الإدارة المحمية الموجودة في 6.4.
revoke update, delete, truncate on public.member_works from anon, authenticated;
grant select, insert on public.member_works to authenticated;

-- 3) تأكيد أن مساحة الملفات الواردة خاصة وليست عامة، مع حد 25 MiB
-- وأنواع الملفات المسموح بها كما في الإعداد السابق.
update storage.buckets
   set public = false,
       file_size_limit = 26214400,
       allowed_mime_types = array[
         'application/pdf',
         'application/msword',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'text/plain'
       ]
 where id = 'member-submissions';

-- منع الدور المجهول anon من قراءة ملفات الإرسال الخاصة حتى لو وُجدت
-- سياسة قراءة عامة permissive قديمة أو أضيفت مستقبلًا.
drop policy if exists "6.5 restrict anonymous private member file reads" on storage.objects;
create policy "6.5 restrict anonymous private member file reads"
  on storage.objects as restrictive for select to anon
  using (bucket_id <> 'member-submissions');

-- سياسات تقييدية تمنع أي سياسة permissive قديمة أو إضافية من توسيع الوصول
-- إلى ملفات member-submissions خارج المالك أو المدير.
drop policy if exists "6.5 restrict private member file reads" on storage.objects;
create policy "6.5 restrict private member file reads"
  on storage.objects as restrictive for select to authenticated
  using (
    bucket_id <> 'member-submissions'
    or (storage.foldername(name))[1] = auth.uid()::text
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

drop policy if exists "6.5 restrict private member file uploads" on storage.objects;
create policy "6.5 restrict private member file uploads"
  on storage.objects as restrictive for insert to authenticated
  with check (
    bucket_id <> 'member-submissions'
    or (
      (storage.foldername(name))[1] = auth.uid()::text
      and (storage.foldername(name))[1] is not null
    )
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

drop policy if exists "6.5 restrict private member file updates" on storage.objects;
create policy "6.5 restrict private member file updates"
  on storage.objects as restrictive for update to authenticated
  using (
    bucket_id <> 'member-submissions'
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  )
  with check (
    bucket_id <> 'member-submissions'
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

drop policy if exists "6.5 restrict private member file deletes" on storage.objects;
create policy "6.5 restrict private member file deletes"
  on storage.objects as restrictive for delete to authenticated
  using (
    bucket_id <> 'member-submissions'
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
    or (
      (storage.foldername(name))[1] = auth.uid()::text
      and not exists (
        select 1 from public.member_works mw
         where mw.user_id = auth.uid()
           and mw.storage_path = name
      )
    )
  );

commit;

-- اختبارات ما بعد التنفيذ (لا تعتبر منفذة بمجرد تشغيل هذا الملف):
-- A) عضو 1 لا يستطيع قراءة ملف عضو 2 الشخصي غير المعتمد أو أعماله.
-- B) الزائر غير المسجل لا يستطيع قراءة member-submissions.
-- C) العضو لا يستطيع إدخال عمل بحالة approved أو تعديل/حذف سجل عمل قائم.
-- D) العضو يستطيع قراءة ملفه وعمله فقط، ورفع ملف داخل مجلد UUID الخاص به.
-- E) العضو لا يستطيع حذف ملف مرتبط بطلب قائم، ولا ملف عضو آخر.
-- F) المدير app_metadata.role=admin يستطيع مراجعة الملفات وإنشاء Signed URL مؤقت.
-- G) الملفات المعتمدة وحدها تُنشر في site-media وفق مسار الاعتماد الموجود.