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
  if actor_email not in ('bigfanoe@gmail.com', '952976@omardblairk8.com') then
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
           auth_user.email,
           profile.display_name
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
