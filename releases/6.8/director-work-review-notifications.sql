-- Scenario & Scenarist 6.8.1: notify directors when a submitted work is reviewed.
-- The notification row intentionally has no related_work_id because that FK
-- currently targets member_works, not director_work_submissions.

create or replace function private.notify_director_work_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.status is distinct from new.status
     and new.status in ('approved', 'rejected') then
    insert into public.member_notifications (
      user_id,
      notification_type,
      title,
      message
    )
    values (
      new.user_id,
      case
        when new.status = 'approved' then 'work_approved'
        else 'work_rejected'
      end,
      case
        when new.status = 'approved' then 'تم اعتماد نموذج عملك الإخراجي'
        else 'نموذج عملك الإخراجي يحتاج إلى تعديل'
      end,
      case
        when new.status = 'approved'
          then 'اعتمدت الإدارة نموذج العمل. سيظهر ضمن ملفك العام ما دام ملفك الشخصي معتمدًا.'
        else 'راجِع ملاحظات الإدارة في حسابك، وعدّل النموذج ثم أعد إرساله للمراجعة.'
      end
    );
  end if;

  return new;
end;
$function$;

revoke all on function private.notify_director_work_review() from public, anon, authenticated;

drop trigger if exists notify_director_work_review on public.director_work_submissions;
create trigger notify_director_work_review
after update of status on public.director_work_submissions
for each row
execute function private.notify_director_work_review();
