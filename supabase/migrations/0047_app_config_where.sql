-- Поправка: на сървъра UPDATE без WHERE се отказва („UPDATE requires a WHERE clause“).
create or replace function public.creator_set_min_build(p_build integer)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  update app_config set min_build = greatest(coalesce(p_build, 0), 0), updated_at = now() where id;
end;
$$;

create or replace function public.creator_set_chat(p_on boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  update app_config set chat_enabled = coalesce(p_on, false), updated_at = now() where id;
end;
$$;
