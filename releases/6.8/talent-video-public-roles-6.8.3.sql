-- Allow both visitors and signed-in members to use the public no-account talent submission flow.
drop policy if exists "Public can upload pending talent audition videos" on storage.objects;
create policy "Public can upload pending talent audition videos"
on storage.objects
for insert
to anon, authenticated
with check (
  bucket_id = 'talent-submission-videos'
  and (storage.foldername(name))[1] = 'pending'
  and storage.extension(name) in ('mp4','webm','mov')
);

drop policy if exists "Public can read approved talent audition videos" on storage.objects;
create policy "Public can read approved talent audition videos"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'talent-submission-videos'
  and exists (
    select 1
    from public.site_content sc
    where sc.content_type = 'talents'
      and sc.published is true
      and sc.content_url = 'talent-video:' || storage.objects.name
  )
);
