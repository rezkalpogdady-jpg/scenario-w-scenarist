-- Scenario & Scenarist 6.7: Academy final project
create table if not exists public.academy_final_projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project_title text not null check (char_length(btrim(project_title)) between 2 and 200),
  genre text not null check (char_length(btrim(genre)) between 2 and 80),
  logline text not null check (char_length(btrim(logline)) between 10 and 700),
  synopsis text not null check (char_length(btrim(synopsis)) between 50 and 6000),
  treatment text not null check (char_length(btrim(treatment)) between 100 and 20000),
  screenplay text not null check (char_length(btrim(screenplay)) between 100 and 120000),
  status text not null default 'draft' check (status in ('draft','pending','approved','needs_revision')),
  admin_feedback text,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint academy_final_projects_one_per_student unique (user_id)
);
alter table public.academy_final_projects alter column status set default 'draft';
create index if not exists academy_final_projects_status_submitted_idx on public.academy_final_projects (status, submitted_at desc);
create index if not exists academy_final_projects_user_id_idx on public.academy_final_projects (user_id);
alter table public.academy_final_projects enable row level security;
drop policy if exists "Students read own final project" on public.academy_final_projects;
create policy "Students read own final project" on public.academy_final_projects for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "Students submit own final project" on public.academy_final_projects;
create policy "Students submit own final project" on public.academy_final_projects for insert to authenticated with check ((select auth.uid()) = user_id and status in ('draft','pending'));
drop policy if exists "Students revise own final project" on public.academy_final_projects;
create policy "Students revise own final project" on public.academy_final_projects for update to authenticated using ((select auth.uid()) = user_id and status in ('draft','needs_revision')) with check ((select auth.uid()) = user_id and status in ('draft','pending'));
drop policy if exists "Platform admins manage academy final projects" on public.academy_final_projects;
create policy "Platform admins manage academy final projects" on public.academy_final_projects for all to authenticated using (is_platform_admin()) with check (is_platform_admin());
grant select, insert, update on public.academy_final_projects to authenticated;

-- Server-side gate: students cannot bypass the 30 lessons + 30 approved assignments requirement.
create or replace function public.guard_academy_final_project_submission()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_completed_count integer := 0;
  v_approved_count integer := 0;
begin
  if public.is_platform_admin() then
    return new;
  end if;
  if v_user_id is null or new.user_id <> v_user_id then
    raise exception 'You may only submit your own final project.';
  end if;
  if tg_op = 'UPDATE' then
    new.admin_feedback := old.admin_feedback;
    new.reviewed_at := old.reviewed_at;
  else
    new.admin_feedback := null;
    new.reviewed_at := null;
  end if;
  if new.status = 'pending' then
    select count(distinct lesson_number) into v_completed_count
      from public.academy_progress where user_id = v_user_id and completed = true;
    select count(distinct lesson_number) into v_approved_count
      from public.academy_assignments where user_id = v_user_id and status = 'approved';
    if v_completed_count < 30 or v_approved_count < 30 then
      raise exception 'Complete all 30 lessons and receive approval for all 30 assignments before submitting the final project.';
    end if;
    new.submitted_at := now();
  end if;
  return new;
end;
$$;
drop trigger if exists academy_final_project_submission_guard on public.academy_final_projects;
create trigger academy_final_project_submission_guard
  before insert or update on public.academy_final_projects
  for each row execute function public.guard_academy_final_project_submission();
revoke all on function public.guard_academy_final_project_submission() from public;
