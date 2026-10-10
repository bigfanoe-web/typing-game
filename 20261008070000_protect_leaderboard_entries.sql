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
  target_is_protected boolean;
  deleted_count integer;
begin
  actor_email := lower(coalesce(auth.jwt() ->> 'email', ''));
  if actor_email not in ('bigfanoe@gmail.com', '952976@omardblairk8.com') then
    raise exception 'Not authorized to remove leaderboard entries.'
      using errcode = '42501';
  end if;

  select exists (
    select 1
      from auth.users as auth_user
      left join public.profiles as profile on profile.id = auth_user.id
      where auth_user.id = p_target_user_id
        and (
          lower(btrim(coalesce(profile.display_name, ''))) in ('schoolriyaz1', 'bigfanoe')
          or lower(btrim(coalesce(auth_user.email, ''))) in ('bigfanoe@gmail.com', '952976@omardblairk8.com')
        )
  )
    into target_is_protected;

  if target_is_protected then
    raise exception 'This player is protected and cannot be removed from the leaderboard.'
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
