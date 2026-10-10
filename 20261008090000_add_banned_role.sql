create or replace function public.grant_profile_role(
  p_target_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor_email text;
  target_email text;
  target_display_name text;
  requested_role text;
begin
  actor_email := lower(coalesce(auth.jwt() ->> 'email', ''));
  if actor_email not in ('bigfanoe@gmail.com', '952976@omardblairk8.com') then
    raise exception 'Not authorized to grant roles.'
      using errcode = '42501';
  end if;

  if p_target_user_id = auth.uid() then
    raise exception 'You cannot grant a role to yourself.'
      using errcode = '42501';
  end if;

  requested_role := lower(btrim(coalesce(p_role, '')));
  if requested_role not in (
    'user', 'admin', 'mod', 'semi owner', 'half owner', 'coowner', 'banned'
  ) then
    raise exception 'Invalid role.'
      using errcode = '22023';
  end if;

  select lower(auth_user.email),
         coalesce(profile.display_name, auth_user.raw_user_meta_data ->> 'display_name')
    into target_email, target_display_name
    from auth.users as auth_user
    left join public.profiles as profile on profile.id = auth_user.id
    where auth_user.id = p_target_user_id;

  if not found then
    raise exception 'Target Auth user not found.'
      using errcode = 'P0002';
  end if;

  if target_email in ('bigfanoe@gmail.com', '952976@omardblairk8.com') then
    raise exception 'Owner roles cannot be changed.'
      using errcode = '42501';
  end if;

  insert into public.profiles (id, email, display_name, role)
    values (
      p_target_user_id,
      target_email,
      coalesce(nullif(btrim(target_display_name), ''), split_part(target_email, '@', 1)),
      requested_role
    )
    on conflict (id) do update
      set email = excluded.email,
          role = excluded.role;
end;
$function$;

revoke all on function public.grant_profile_role(uuid, text) from public;
revoke all on function public.grant_profile_role(uuid, text) from anon;
grant execute on function public.grant_profile_role(uuid, text) to authenticated;

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
  player_role text;
begin
  player_id := auth.uid();
  if player_id is null then
    raise exception 'Sign in to submit a leaderboard score.'
      using errcode = '42501';
  end if;

  select lower(btrim(coalesce(profile.role, 'user')))
    into player_role
    from public.profiles as profile
    where profile.id = player_id;

  if player_role = 'banned' then
    raise exception 'Banned accounts cannot submit leaderboard scores.'
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
