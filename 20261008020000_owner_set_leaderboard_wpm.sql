create or replace function public.owner_set_leaderboard_wpm(
  p_target_user_id uuid,
  p_best_wpm integer
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor_email text;
begin
  actor_email := lower(coalesce(auth.jwt() ->> 'email', ''));
  if actor_email not in ('bigfanoe@gmail.com', '952976@omardblairk8.com') then
    raise exception 'Not authorized to change leaderboard scores.'
      using errcode = '42501';
  end if;

  if p_best_wpm is null or p_best_wpm not between 1 and 1000 then
    raise exception 'WPM must be between 1 and 1000.'
      using errcode = '22023';
  end if;

  if not exists (select 1 from auth.users where id = p_target_user_id) then
    raise exception 'Target Auth user not found.'
      using errcode = 'P0002';
  end if;

  insert into public.leaderboard_scores (
    user_id, best_wpm, accuracy, duration_seconds, updated_at
  )
  values (p_target_user_id, p_best_wpm, 100, 60, now())
  on conflict (user_id) do update
    set best_wpm = excluded.best_wpm,
        updated_at = excluded.updated_at;
end;
$function$;

revoke all on function public.owner_set_leaderboard_wpm(uuid, integer) from public;
revoke all on function public.owner_set_leaderboard_wpm(uuid, integer) from anon;
grant execute on function public.owner_set_leaderboard_wpm(uuid, integer) to authenticated;
