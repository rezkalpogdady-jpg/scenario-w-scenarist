-- 6.8.57: Allow anonymous visitors to read only approved, published scenario PDFs.
-- The bucket remains private; access is granted per object through this policy.
drop policy if exists "Public read approved scenario PDFs" on storage.objects;

create policy "Public read approved scenario PDFs"
on storage.objects
for select
to anon
using (
  bucket_id = 'scenario-scripts'
  and exists (
    select 1
    from public.scenario_scripts as s
    where s.storage_path = objects.name
      and s.published = true
      and s.rights_confirmed = true
      and s.rights_status <> 'unverified'
      and nullif(btrim(s.rights_holder), '') is not null
  )
);
