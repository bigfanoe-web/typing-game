do $migration$
begin
  if exists (
    select 1
      from public.profiles
      where display_name is not null
        and btrim(display_name) <> ''
      group by lower(btrim(display_name))
      having count(*) > 1
  ) then
    raise exception 'Cannot enforce unique usernames while duplicate display names exist. Change the duplicates in public.profiles, then run this migration again.';
  end if;
end;
$migration$;

create unique index if not exists profiles_display_name_normalized_unique
  on public.profiles (lower(btrim(display_name)))
  where display_name is not null
    and btrim(display_name) <> '';
