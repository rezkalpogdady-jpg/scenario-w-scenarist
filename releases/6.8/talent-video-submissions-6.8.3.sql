-- Scenario & Scenarist 6.8.3
-- Private video bucket for anonymous talent audition submissions.
-- Videos are readable by the public only after an admin publishes the related talent card.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'talent-submission-videos',
  'talent-submission-videos',
  false,
  52428800,
  array['video/mp4','video/webm','video/quicktime']
)
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public can upload pending talent audition videos" on storage.objects;
create policy "Public can upload pending talent audition videos"
on storage.objects
for insert
to anon
with check (
  bucket_id = 'talent-submission-videos'
  and (storage.foldername(name))[1] = 'pending'
  and storage.extension(name) in ('mp4','webm','mov')
);

drop policy if exists "Public can read approved talent audition videos" on storage.objects;
create policy "Public can read approved talent audition videos"
on storage.objects
for select
to anon
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

drop policy if exists "Admins can read talent audition videos" on storage.objects;
create policy "Admins can read talent audition videos"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'talent-submission-videos'
  and private.is_platform_admin()
);

drop policy if exists "Admins can delete talent audition videos" on storage.objects;
create policy "Admins can delete talent audition videos"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'talent-submission-videos'
  and private.is_platform_admin()
);
