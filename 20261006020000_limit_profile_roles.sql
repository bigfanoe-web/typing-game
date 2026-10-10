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
    'user', 'vip', 'moderator', 'tester', 'admin', 'senior admin', 'co-owner'
  ) then
    raise exception 'Invalid role.'
      using errcode = '22023';
  end if;

  select lower(email)
    into target_email
    from public.profiles
    where id = p_target_user_id
    for update;

  if not found then
    raise exception 'Target profile not found.'
      using errcode = 'P0002';
  end if;

  if target_email in ('bigfanoe@gmail.com', '952976@omardblairk8.com') then
    raise exception 'Owner roles cannot be changed.'
      using errcode = '42501';
  end if;

  update public.profiles
    set role = requested_role
    where id = p_target_user_id;
end;
$function$;

revoke all on function public.grant_profile_role(uuid, text) from public;
revoke all on function public.grant_profile_role(uuid, text) from anon;
grant execute on function public.grant_profile_role(uuid, text) to authenticated;
