alter table public.leaderboard_scores
  drop constraint if exists leaderboard_scores_best_wpm_check;

alter table public.leaderboard_scores
  add constraint leaderboard_scores_best_wpm_check
  check (best_wpm between 1 and 10000000);

create or replace function public.submit_leaderboard_score(
  p_best_wpm integer,
  p_accuracy integer,
  p_duration_seconds integer
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  player_id uuid;
begin
  player_id := auth.uid();
  if player_id is null then
    raise exception 'Sign in to submit a leaderboard score.'
      using errcode = '42501';
  end if;

  if p_best_wpm is null or p_best_wpm not between 1 and 10000000
     or p_accuracy is null or p_accuracy not between 0 and 100
     or p_duration_seconds is null or p_duration_seconds not between 5 and 3600 then
    raise exception 'Invalid leaderboard score.'
      using errcode = '22023';
  end if;

  insert into public.leaderboard_scores (
    user_id, best_wpm, accuracy, duration_seconds, updated_at
  )
  values (player_id, p_best_wpm, p_accuracy, p_duration_seconds, now())
  on conflict (user_id) do update
    set best_wpm = excluded.best_wpm,
        accuracy = excluded.accuracy,
        duration_seconds = excluded.duration_seconds,
        updated_at = excluded.updated_at
    where excluded.best_wpm > public.leaderboard_scores.best_wpm;
end;
$function$;

revoke all on function public.submit_leaderboard_score(integer, integer, integer) from public;
revoke all on function public.submit_leaderboard_score(integer, integer, integer) from anon;
grant execute on function public.submit_leaderboard_score(integer, integer, integer) to authenticated;

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

  if p_best_wpm is null or p_best_wpm not between 1 and 10000000 then
    raise exception 'WPM must be between 1 and 10000000.'
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
