-- =====================================================================
-- Muutoshistoria ei enää näytä laitetunnistetta (päätetty 28.10.2026).
--
-- Tieto muutoksen tehneestä istunnosta säilyy lokitaulussa ylläpitäjää
-- varten, mutta selaimelle palautetaan vain:
--   - tekikö muutoksen tämä laite (actor_is_me)
--   - tekikö poiston varauksen tehnyt laite (actor_is_owner, vain poistoissa)
--   - tekikö muutoksen ylläpito (by_admin)
-- Eri muutosten tekijöitä ei siis voi verrata keskenään.
--
-- Muuttaa vain list_booking_log-funktiota. Lokidataan ei kosketa.
-- Aja tämä Supabasen SQL Editorissa ENNEN kuin uusi käyttöliittymä julkaistaan.
-- =====================================================================

begin;

drop function if exists public.list_booking_log(text);

create function public.list_booking_log(p_token text)
returns table (
  logged_at        timestamptz,
  action           text,
  device_id        smallint,
  apartment_number text,
  start_at         timestamptz,
  end_at           timestamptz,
  previous_end_at  timestamptz,
  by_admin         boolean,
  actor_is_me      boolean,
  actor_is_owner   boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session uuid := app_private.require_session(p_token);
begin
  return query
    select l.logged_at, l.action, l.device_id, l.apartment_number, l.start_at, l.end_at, l.previous_end_at,
           l.actor_session is null,
           coalesce(l.actor_session = v_session, false),
           case when l.action = 'deleted' and l.actor_session is not null
                then coalesce(l.actor_session = l.owner_session, false) end
    from app_private.booking_log l
    where l.logged_at > now() - interval '90 days'
    order by l.logged_at desc, l.id desc
    limit 200;
end;
$$;

revoke execute on function public.list_booking_log(text) from public;
grant execute on function public.list_booking_log(text) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
