create table if not exists public.leaderboard_scores (
  user_id uuid primary key references auth.users (id) on delete cascade,
  best_wpm integer not null check (best_wpm between 1 and 1000),
  accuracy integer not null check (accuracy between 0 and 100),
  duration_seconds integer not null check (duration_seconds between 5 and 3600),
  updated_at timestamptz not null default now()
);

alter table public.leaderboard_scores enable row level security;
revoke all on table public.leaderboard_scores from anon, authenticated;

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

  if p_best_wpm is null or p_best_wpm not between 1 and 1000
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

create or replace function public.get_public_leaderboard()
returns table (
  rank_position bigint,
  player_name text,
  accuracy integer,
  best_wpm integer
)
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select row_number() over (order by scores.best_wpm desc, scores.updated_at asc) as rank_position,
         coalesce(
           nullif(btrim(profile.display_name), ''),
           nullif(split_part(auth_user.email, '@', 1), ''),
           'Player'
         )::text as player_name,
         scores.accuracy,
         scores.best_wpm
  from public.leaderboard_scores as scores
  join auth.users as auth_user on auth_user.id = scores.user_id
  left join public.profiles as profile on profile.id = scores.user_id
  order by scores.best_wpm desc, scores.updated_at asc
  limit 10;
$function$;

revoke all on function public.get_public_leaderboard() from public;
grant execute on function public.get_public_leaderboard() to anon, authenticated;
