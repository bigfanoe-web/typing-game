do $migration$
declare
  profile_table oid := 'public.profiles'::regclass;
  display_name_attnum smallint;
  unique_constraint record;
  unique_index record;
begin
  select attribute.attnum
    into display_name_attnum
    from pg_attribute as attribute
    where attribute.attrelid = profile_table
      and attribute.attname = 'display_name'
      and not attribute.attisdropped;

  if display_name_attnum is null then
    raise exception 'public.profiles.display_name does not exist.';
  end if;

  for unique_constraint in
    select constraint_row.conname
      from pg_constraint as constraint_row
      where constraint_row.conrelid = profile_table
        and constraint_row.contype = 'u'
        and constraint_row.conkey = array[display_name_attnum]::smallint[]
  loop
    execute format(
      'alter table public.profiles drop constraint %I',
      unique_constraint.conname
    );
  end loop;

  for unique_index in
    select namespace.nspname as schema_name,
           index_relation.relname as index_name
      from pg_index as index_row
      join pg_class as index_relation on index_relation.oid = index_row.indexrelid
      join pg_namespace as namespace on namespace.oid = index_relation.relnamespace
      where index_row.indrelid = profile_table
        and index_row.indisunique
        and not index_row.indisprimary
        and index_row.indnkeyatts = 1
        and index_row.indkey[0] = display_name_attnum
        and not exists (
          select 1
            from pg_constraint as constraint_row
            where constraint_row.conindid = index_row.indexrelid
        )
  loop
    execute format(
      'drop index %I.%I',
      unique_index.schema_name,
      unique_index.index_name
    );
  end loop;
end;
$migration$;
