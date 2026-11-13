-- The original member-number auth migration already defines both cascading
-- foreign keys. Remove the redundant copies added by the follow-up hardening migration.
ALTER TABLE public.member_login_directory
  DROP CONSTRAINT IF EXISTS member_login_directory_user_id_auth_fkey;
ALTER TABLE public.member_private_details
  DROP CONSTRAINT IF EXISTS member_private_details_user_id_auth_fkey;
