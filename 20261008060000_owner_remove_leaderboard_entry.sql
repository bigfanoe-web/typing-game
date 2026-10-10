create or replace function public.owner_remove_leaderboard_entry(
  p_target_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor_email text;
  deleted_count integer;
begin
  actor_email := lower(coalesce(auth.jwt() ->> 'email', ''));
  if actor_email not in ('bigfanoe@gmail.com', '952976@omardblairk8.com') then
    raise exception 'Not authorized to remove leaderboard entries.'
      using errcode = '42501';
  end if;

  delete from public.leaderboard_scores
    where user_id = p_target_user_id;
  get diagnostics deleted_count = row_count;

  return deleted_count > 0;
end;
$function$;

revoke all on function public.owner_remove_leaderboard_entry(uuid) from public;
revoke all on function public.owner_remove_leaderboard_entry(uuid) from anon;
grant execute on function public.owner_remove_leaderboard_entry(uuid) to authenticated;
