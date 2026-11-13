-- Require current admin_users membership for sensitive RLS operations.
-- This prevents a removed admin's still-valid JWT app_metadata from retaining
-- moderation and contact-message privileges until token expiry.

DROP POLICY IF EXISTS "Admins delete crime stories" ON public.crime_stories;
CREATE POLICY "Admins delete crime stories"
ON public.crime_stories FOR DELETE TO authenticated
USING (private.is_platform_admin());

DROP POLICY IF EXISTS "Admins update crime stories" ON public.crime_stories;
CREATE POLICY "Admins update crime stories"
ON public.crime_stories FOR UPDATE TO authenticated
USING (private.is_platform_admin())
WITH CHECK (private.is_platform_admin());

DROP POLICY IF EXISTS "Members read published crime stories" ON public.crime_stories;
CREATE POLICY "Members read published crime stories"
ON public.crime_stories FOR SELECT TO authenticated
USING ((is_published = true AND status = 'approved') OR private.is_platform_admin());

DROP POLICY IF EXISTS "Members submit crime stories or admin publish" ON public.crime_stories;
CREATE POLICY "Members submit crime stories or admin publish"
ON public.crime_stories FOR INSERT TO authenticated
WITH CHECK (
  private.is_platform_admin()
  OR (
    is_published = false
    AND status = 'pending'
    AND char_length(btrim(title)) BETWEEN 3 AND 180
    AND content IS NOT NULL
    AND char_length(btrim(content)) BETWEEN 40 AND 30000
    AND (author_name IS NULL OR char_length(btrim(author_name)) <= 120)
    AND (category IS NULL OR char_length(btrim(category)) <= 80)
  )
);

DROP POLICY IF EXISTS "Platform admins can read contact messages" ON public.platform_contact_messages;
CREATE POLICY "Platform admins can read contact messages"
ON public.platform_contact_messages FOR SELECT TO authenticated
USING (private.is_platform_admin());

DROP POLICY IF EXISTS "Platform admins can update contact messages" ON public.platform_contact_messages;
CREATE POLICY "Platform admins can update contact messages"
ON public.platform_contact_messages FOR UPDATE TO authenticated
USING (private.is_platform_admin())
WITH CHECK (private.is_platform_admin());
