-- 6.8.51: ملفات PDF الخاصة بالكُتّاب، مستقلة عن مكتبة السيناريوهات
create table if not exists public.writer_scripts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.member_profiles(user_id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 180),
  category text not null check (category in ('feature','short','series','episode','theatre','other')),
  summary text not null default '' check (char_length(summary) <= 1800),
  storage_path text not null,
  published_storage_path text,
  status text not null default 'pending' check (status in ('pending','approved','needs_revision')),
  review_notes text,
  rights_confirmed boolean not null default false,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  revision_count integer not null default 0 check (revision_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint writer_scripts_storage_owner_path check (storage_path like user_id::text || '/%'),
  constraint writer_scripts_approved_requires_publication check (
    status <> 'approved' or (rights_confirmed and published_storage_path is not null)
  )
);

-- لا تسمح للكاتب بتزوير قرار الإدارة أو مسار النسخة المنشورة.
create or replace function private.guard_writer_script_owner_changes()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if not private.is_platform_admin() then
    if tg_op = 'INSERT' then
      new.status := 'pending';
      new.published_storage_path := null;
      new.review_notes := null;
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.revision_count := 0;
    else
      if new.user_id is distinct from old.user_id
        or new.published_storage_path is distinct from old.published_storage_path
        or new.reviewed_by is distinct from old.reviewed_by
        or new.reviewed_at is distinct from old.reviewed_at then
        raise exception 'Writer review fields are managed by the platform team';
      end if;
      new.status := 'pending';
      new.review_notes := null;
      new.reviewed_by := null;
      new.reviewed_at := null;
      if old.status = 'needs_revision' then
        new.revision_count := old.revision_count + 1;
      else
        new.revision_count := old.revision_count;
      end if;
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists guard_writer_script_owner_changes on public.writer_scripts;
create trigger guard_writer_script_owner_changes
  before insert or update on public.writer_scripts
  for each row execute function private.guard_writer_script_owner_changes();

create index if not exists writer_scripts_user_created_idx
  on public.writer_scripts(user_id, created_at desc);
create index if not exists writer_scripts_status_created_idx
  on public.writer_scripts(status, created_at desc);

alter table public.writer_scripts enable row level security;

grant select on public.writer_scripts to anon, authenticated;
grant insert, update on public.writer_scripts to authenticated;

drop policy if exists "Writers read own scripts" on public.writer_scripts;
create policy "Writers read own scripts"
  on public.writer_scripts for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Admins read all writer scripts" on public.writer_scripts;
create policy "Admins read all writer scripts"
  on public.writer_scripts for select to authenticated
  using (private.is_platform_admin());

drop policy if exists "Public read approved writer scripts" on public.writer_scripts;
create policy "Public read approved writer scripts"
  on public.writer_scripts for select to anon, authenticated
  using (
    status = 'approved'
    and exists (
      select 1 from public.member_profiles mp
      where mp.user_id = writer_scripts.user_id
        and mp.account_type = 'writer'
        and mp.profile_status = 'approved'
    )
  );

drop policy if exists "Writers submit own PDF scripts" on public.writer_scripts;
create policy "Writers submit own PDF scripts"
  on public.writer_scripts for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and status = 'pending'
    and rights_confirmed = true
    and storage_path like (select auth.uid())::text || '/%'
    and exists (
      select 1 from public.member_profiles mp
      where mp.user_id = (select auth.uid())
        and mp.account_type = 'writer'
    )
  );

drop policy if exists "Writers resubmit scripts needing revision" on public.writer_scripts;
create policy "Writers resubmit scripts needing revision"
  on public.writer_scripts for update to authenticated
  using (
    (select auth.uid()) = user_id
    and status in ('pending','approved','needs_revision')
    and exists (
      select 1 from public.member_profiles mp
      where mp.user_id = (select auth.uid())
        and mp.account_type = 'writer'
    )
  )
  with check (
    (select auth.uid()) = user_id
    and status = 'pending'
    and rights_confirmed = true
    and storage_path like (select auth.uid())::text || '/%'
  );

drop policy if exists "Admins manage writer scripts" on public.writer_scripts;
create policy "Admins manage writer scripts"
  on public.writer_scripts for all to authenticated
  using (private.is_platform_admin())
  with check (private.is_platform_admin());

-- يسمح للزوار بقراءة ملفات السيناريو المعتمدة فقط، دون فتح ملفات المراجعة الخاصة.
drop policy if exists "Writers read own approved writer script PDFs" on storage.objects;
create policy "Writers read own approved writer script PDFs"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'scenario-scripts'
    and exists (
      select 1 from public.writer_scripts ws
      where ws.published_storage_path = objects.name
        and ws.status = 'approved'
        and ws.user_id = (select auth.uid())
    )
  );

drop policy if exists "Public read approved writer script PDFs" on storage.objects;
create policy "Public read approved writer script PDFs"
  on storage.objects for select to anon, authenticated
  using (
    bucket_id = 'scenario-scripts'
    and exists (
      select 1
      from public.writer_scripts ws
      join public.member_profiles mp on mp.user_id = ws.user_id
      where ws.published_storage_path = objects.name
        and ws.status = 'approved'
        and mp.account_type = 'writer'
        and mp.profile_status = 'approved'
    )
  );

-- يسمح للكاتب برفع ملف المراجعة إلى مجلده الخاص فقط داخل مساحة الملفات الخاصة.
drop policy if exists "Writers upload own private script PDFs" on storage.objects;
create policy "Writers upload own private script PDFs"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'member-submissions'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (storage.foldername(name))[2] = 'writer-scripts'
    and lower(storage.extension(name)) = 'pdf'
  );
