-- 6.8.99: allow members to publish their own profiles and comments immediately.
-- Keep ownership checks, posting blocks, and server-side rate limits in place.

DROP POLICY IF EXISTS "Members can create own profile" ON public.member_profiles;
CREATE POLICY "Members can create own published profile"
ON public.member_profiles
FOR INSERT
TO authenticated
WITH CHECK (
  (SELECT auth.uid()) = user_id
  AND profile_status = 'approved'
);

DROP POLICY IF EXISTS "Members can submit content comments" ON public.content_comments;
CREATE POLICY "Members can publish content comments"
ON public.content_comments
FOR INSERT
TO authenticated
WITH CHECK (
  (SELECT auth.uid()) = user_id
  AND status = 'approved'
  AND NOT EXISTS (
    SELECT 1
    FROM public.member_posting_blocks b
    WHERE b.user_id = (SELECT auth.uid())
  )
  AND (SELECT private.can_submit_content_comment())
  AND (
    (
      content_id IS NOT NULL
      AND crime_story_id IS NULL
      AND EXISTS (
        SELECT 1
        FROM public.site_content c
        WHERE c.id = content_comments.content_id
          AND c.published = true
      )
    )
    OR
    (
      content_id IS NULL
      AND crime_story_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.crime_stories s
        WHERE s.id = content_comments.crime_story_id
          AND s.is_published = true
          AND s.status = 'approved'
      )
    )
  )
);

CREATE OR REPLACE FUNCTION private.can_submit_topic_reply()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user uuid := (SELECT auth.uid());
  v_count bigint;
BEGIN
  IF v_user IS NULL THEN
    RETURN false;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text, 1)
  );

  SELECT count(*)
  INTO v_count
  FROM public.topic_replies
  WHERE user_id = v_user
    AND created_at > now() - interval '1 minute';

  RETURN v_count < 5;
END;
$function$;

REVOKE ALL ON FUNCTION private.can_submit_topic_reply() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.can_submit_topic_reply() TO authenticated;

DROP POLICY IF EXISTS "Members can submit topic replies" ON public.topic_replies;
CREATE POLICY "Members can publish topic replies"
ON public.topic_replies
FOR INSERT
TO authenticated
WITH CHECK (
  (SELECT auth.uid()) = user_id
  AND status = 'approved'
  AND length(btrim(body)) BETWEEN 1 AND 2000
  AND NOT EXISTS (
    SELECT 1
    FROM public.member_posting_blocks b
    WHERE b.user_id = (SELECT auth.uid())
  )
  AND (SELECT private.can_submit_topic_reply())
  AND EXISTS (
    SELECT 1
    FROM public.community_topics t
    WHERE t.id = topic_replies.topic_id
      AND t.status = 'approved'
  )
);
