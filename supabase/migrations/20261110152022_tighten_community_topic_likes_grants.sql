revoke all on table public.community_topic_likes from anon, authenticated, service_role;
grant insert, delete on table public.community_topic_likes to authenticated;
revoke all on function public.get_community_topic_like_stats(uuid[]) from public, anon;
grant execute on function public.get_community_topic_like_stats(uuid[]) to authenticated;
