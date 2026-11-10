alter table public.crime_stories
  add column if not exists author_name text,
  add column if not exists contact text,
  add column if not exists category text,
  add column if not exists status text not null default 'pending',
  add column if not exists reviewed_at timestamptz;

update public.crime_stories
set status = case when is_published then 'approved' else 'pending' end
where status = 'pending' and is_published = true;

alter table public.crime_stories
  drop constraint if exists crime_stories_status_check;
alter table public.crime_stories
  add constraint crime_stories_status_check
  check (status in ('pending','approved','rejected'));

alter table public.crime_stories
  drop constraint if exists crime_stories_submission_lengths_check;
alter table public.crime_stories
  add constraint crime_stories_submission_lengths_check
  check (
    char_length(btrim(title)) between 3 and 180
    and (description is null or char_length(description) <= 2500)
    and (content is null or char_length(content) <= 30000)
    and (author_name is null or char_length(btrim(author_name)) <= 120)
    and (contact is null or char_length(btrim(contact)) <= 180)
    and (category is null or char_length(btrim(category)) <= 80)
  );

create index if not exists crime_stories_publication_idx
  on public.crime_stories (is_published, created_at desc);
create index if not exists crime_stories_review_queue_idx
  on public.crime_stories (status, created_at desc);

drop policy if exists "Public submit crime stories for review" on public.crime_stories;
create policy "Public submit crime stories for review"
  on public.crime_stories
  for insert
  to anon, authenticated
  with check (
    is_published = false
    and status = 'pending'
    and char_length(btrim(title)) between 3 and 180
    and content is not null
    and char_length(btrim(content)) between 40 and 30000
    and (author_name is null or char_length(btrim(author_name)) <= 120)
    and (contact is null or char_length(btrim(contact)) <= 180)
    and (category is null or char_length(btrim(category)) <= 80)
  );

grant select on public.crime_stories to anon, authenticated;
grant insert on public.crime_stories to anon, authenticated;
grant usage, select on sequence public.crime_stories_id_seq to authenticated, service_role;
