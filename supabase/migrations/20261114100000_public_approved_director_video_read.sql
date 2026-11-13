-- Allow logged-out visitors to create signed URLs for approved director work videos only.
-- Keep the bucket private; pending submissions and unapproved profiles remain inaccessible.
-- Idempotent because the policy was also applied directly to the live project.
drop policy if exists "Public can read approved director work videos" on storage.objects;

create policy "Public can read approved director work videos"
on storage.objects
for select
to anon
using (
  bucket_id = 'director-work-videos'
  and exists (
    select 1
    from public.director_work_submissions w
    join public.member_profiles mp on mp.user_id = w.user_id
    where w.storage_path = objects.name
      and w.status = 'approved'
      and mp.account_type = 'director'
      and mp.profile_status = 'approved'
  )
);
