create or replace function public.find_profile_for_role_grant(p_query text)
returns table (id uuid, email text, display_name text)
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor_email text;
  normalized_query text;
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

  return query
    select profile.id, profile.email, profile.display_name
    from public.profiles as profile
    where lower(btrim(coalesce(profile.email, ''))) = normalized_query
       or lower(btrim(coalesce(profile.display_name, ''))) = normalized_query;
end;
$function$;

revoke all on function public.find_profile_for_role_grant(text) from public;
revoke all on function public.find_profile_for_role_grant(text) from anon;
grant execute on function public.find_profile_for_role_grant(text) to authenticated;
