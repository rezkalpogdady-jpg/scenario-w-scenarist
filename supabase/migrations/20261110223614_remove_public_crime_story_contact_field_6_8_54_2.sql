drop policy if exists "Submit crime stories or admin publish" on public.crime_stories;
create policy "Submit crime stories or admin publish"
  on public.crime_stories for insert to anon, authenticated
  with check (
    coalesce((select auth.jwt())->'app_metadata'->>'role' = 'admin', false)
    or (
      is_published = false and status = 'pending'
      and char_length(btrim(title)) between 3 and 180
      and content is not null and char_length(btrim(content)) between 40 and 30000
      and (author_name is null or char_length(btrim(author_name)) <= 120)
      and (category is null or char_length(btrim(category)) <= 80)
    )
  );
alter table public.crime_stories drop column if exists contact;