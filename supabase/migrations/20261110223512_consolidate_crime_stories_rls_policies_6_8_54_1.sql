drop policy if exists "Admin manage crime stories" on public.crime_stories;
drop policy if exists "Public read crime stories" on public.crime_stories;
drop policy if exists "Public submit crime stories for review" on public.crime_stories;

create policy "Read published crime stories or admin"
  on public.crime_stories
  for select
  to anon, authenticated
  using (is_published = true or (select private.is_platform_admin()));

create policy "Submit crime stories or admin publish"
  on public.crime_stories
  for insert
  to anon, authenticated
  with check (
    (select private.is_platform_admin())
    or (
      is_published = false
      and status = 'pending'
      and char_length(btrim(title)) between 3 and 180
      and content is not null
      and char_length(btrim(content)) between 40 and 30000
      and (author_name is null or char_length(btrim(author_name)) <= 120)
      and (contact is null or char_length(btrim(contact)) <= 180)
      and (category is null or char_length(btrim(category)) <= 80)
    )
  );

create policy "Admins update crime stories"
  on public.crime_stories
  for update
  to authenticated
  using ((select private.is_platform_admin()))
  with check ((select private.is_platform_admin()));

create policy "Admins delete crime stories"
  on public.crime_stories
  for delete
  to authenticated
  using ((select private.is_platform_admin()));
