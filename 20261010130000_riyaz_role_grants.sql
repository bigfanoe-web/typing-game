create table if not exists public.profile_role_grant_owners (
  user_id uuid primary key references auth.users (id) on delete cascade
);

alter table public.profile_role_grant_owners enable row level security;
revoke all on table public.profile_role_grant_owners from public, anon, authenticated;

insert into public.profile_role_grant_owners (user_id)
select auth_user.id
  from auth.users as auth_user
  left join public.profiles as profile on profile.id = auth_user.id
  where lower(btrim(coalesce(
          nullif(profile.display_name, ''),
          auth_user.raw_user_meta_data ->> 'display_name',
          ''
        )))
        in ('schoolriyaz1', 'bigfanoe')
     or lower(btrim(coalesce(auth_user.email, '')))
        in ('bigfanoe@gmail.com', '952976@omardblairk8.com')
on conflict (user_id) do nothing;

create or replace function public.find_profile_for_role_grant(p_query text)
returns table (id uuid, email text, display_name text)
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor_email text;
  normalized_query text;
  target_id uuid;
begin
  actor_email := lower(coalesce(auth.jwt() ->> 'email', ''));
  if actor_email not in ('bigfanoe@gmail.com', '952976@omardblairk8.com')
     and not exists (
       select 1
         from public.profile_role_grant_owners as grant_owner
         where grant_owner.user_id = auth.uid()
     ) then
    raise exception 'Not authorized to look up players.'
      using errcode = '42501';
  end if;

  normalized_query := lower(btrim(coalesce(p_query, '')));
  if normalized_query = '' then
    return;
  end if;

  if normalized_query ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    target_id := normalized_query::uuid;
  end if;

  return query
    select auth_user.id,
           auth_user.email::text,
           profile.display_name::text
      from auth.users as auth_user
      left join public.profiles as profile on profile.id = auth_user.id
      where (target_id is not null and auth_user.id = target_id)
         or lower(btrim(coalesce(auth_user.email, ''))) = normalized_query
         or lower(btrim(coalesce(profile.display_name, ''))) = normalized_query;
end;
$function$;

revoke all on function public.find_profile_for_role_grant(text) from public;
revoke all on function public.find_profile_for_role_grant(text) from anon;
grant execute on function public.find_profile_for_role_grant(text) to authenticated;

create or replace function public.is_profile_role_grant_owner()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select lower(coalesce(auth.jwt() ->> 'email', ''))
           in ('bigfanoe@gmail.com', '952976@omardblairk8.com')
      or exists (
        select 1
          from public.profile_role_grant_owners as grant_owner
          where grant_owner.user_id = auth.uid()
      );
$function$;

revoke all on function public.is_profile_role_grant_owner() from public;
revoke all on function public.is_profile_role_grant_owner() from anon;
grant execute on function public.is_profile_role_grant_owner() to authenticated;

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
  if actor_email not in ('bigfanoe@gmail.com', '952976@omardblairk8.com')
     and not exists (
       select 1
         from public.profile_role_grant_owners as grant_owner
         where grant_owner.user_id = auth.uid()
     ) then
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

  if target_email in ('bigfanoe@gmail.com', '952976@omardblairk8.com')
     or exists (
       select 1
         from public.profile_role_grant_owners as grant_owner
         where grant_owner.user_id = p_target_user_id
     ) then
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
