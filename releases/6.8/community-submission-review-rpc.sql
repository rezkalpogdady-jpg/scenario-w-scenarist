-- Scenario & Scenarist 6.8.2
-- Restore the admin review RPC used by anonymous talent and project submissions.
-- SECURITY INVOKER is intentional: admin authorization and table RLS remain active.

create or replace function public.admin_review_community_submission(
  p_submission_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_submission public.community_submissions%rowtype;
  v_content_id uuid;
begin
  if not coalesce(private.is_platform_admin(), false) then
    raise exception 'غير مصرح بمراجعة طلبات المجتمع'
      using errcode = '42501';
  end if;

  if p_status is null or p_status not in ('approved', 'rejected') then
    raise exception 'حالة المراجعة غير صالحة'
      using errcode = '22023';
  end if;

  select *
    into v_submission
    from public.community_submissions
   where id = p_submission_id
   for update;

  if not found then
    raise exception 'الطلب غير موجود'
      using errcode = 'P0002';
  end if;

  if v_submission.status <> 'pending' then
    raise exception 'تمت مراجعة هذا الطلب من قبل'
      using errcode = '55000';
  end if;

  if p_status = 'approved' then
    if v_submission.submission_type = 'talent' then
      insert into public.site_content (
        content_type, title, category, description, content_url,
        extra_data, published
      )
      values (
        'talents',
        v_submission.name,
        v_submission.category,
        coalesce(v_submission.bio, ''),
        v_submission.work_url,
        jsonb_build_object(
          'name', v_submission.name,
          'type', v_submission.category,
          'city', coalesce(v_submission.city, ''),
          'submission_id', v_submission.id
        ),
        true
      )
      returning id into v_content_id;
    elsif v_submission.submission_type = 'project' then
      insert into public.site_content (
        content_type, title, category, description, content_url,
        extra_data, published
      )
      values (
        'production',
        v_submission.title,
        v_submission.category,
        coalesce(v_submission.description, ''),
        v_submission.work_url,
        jsonb_build_object(
          'owner', coalesce(v_submission.owner_name, ''),
          'submission_id', v_submission.id
        ),
        true
      )
      returning id into v_content_id;
    else
      raise exception 'نوع الطلب غير مدعوم'
        using errcode = '22023';
    end if;
  end if;

  update public.community_submissions
     set status = p_status,
         reviewed_at = now()
   where id = p_submission_id;

  return jsonb_build_object(
    'submission_id', p_submission_id,
    'status', p_status,
    'published_content_id', v_content_id
  );
end;
$function$;

revoke all on function public.admin_review_community_submission(uuid, text) from public, anon;
grant execute on function public.admin_review_community_submission(uuid, text) to authenticated;
