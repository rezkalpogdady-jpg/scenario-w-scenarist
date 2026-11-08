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
