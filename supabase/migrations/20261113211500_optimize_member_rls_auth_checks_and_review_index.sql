-- Reduce per-row auth function evaluation in high-traffic RLS policies.
-- Preserve the same access rules while allowing PostgreSQL to evaluate auth.uid()
-- once per statement. Add the missing index for writer_scripts.reviewed_by FK.

DROP POLICY IF EXISTS "Members read non-restricted published site content" ON public.site_content;
CREATE POLICY "Members read non-restricted published site content"
ON public.site_content FOR SELECT TO anon, authenticated
USING (published = true AND (content_type <> 'films' OR (select auth.uid()) IS NOT NULL));

DROP POLICY IF EXISTS "Members can delete own pending topics" ON public.community_topics;
CREATE POLICY "Members can delete own pending topics"
ON public.community_topics FOR DELETE TO authenticated
USING ((select auth.uid()) = user_id AND status = 'pending');

DROP POLICY IF EXISTS "Members can delete own pending replies" ON public.topic_replies;
CREATE POLICY "Members can delete own pending replies"
ON public.topic_replies FOR DELETE TO authenticated
USING ((select auth.uid()) = user_id AND status = 'pending');

DROP POLICY IF EXISTS "Members can add own ratings" ON public.content_ratings;
CREATE POLICY "Members can add own ratings"
ON public.content_ratings FOR INSERT TO authenticated
WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Members can update own ratings" ON public.content_ratings;
CREATE POLICY "Members can update own ratings"
ON public.content_ratings FOR UPDATE TO authenticated
USING ((select auth.uid()) = user_id)
WITH CHECK ((select auth.uid()) = user_id);

CREATE INDEX IF NOT EXISTS writer_scripts_reviewed_by_idx
ON public.writer_scripts (reviewed_by)
WHERE reviewed_by IS NOT NULL;
