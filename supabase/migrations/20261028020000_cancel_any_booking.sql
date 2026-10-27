-- =====================================================================
-- Kuka tahansa kirjautunut käyttäjä voi poistaa minkä tahansa tulevan tai
-- käynnissä olevan varauksen (päätetty 27.10.2026). Käyttöliittymä kysyy
-- vahvistuksen ennen poistoa. Poisto vaatii edelleen voimassa olevan
-- istunnon, eikä päättyneitä varauksia voi poistaa.
--
-- Aja tämä Supabasen SQL Editorissa aiempien migraatioiden jälkeen.
-- =====================================================================

begin;

create or replace function public.cancel_booking(p_token text, p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.require_session(p_token);

  delete from app_private.bookings b
  where b.id = p_booking_id
    and b.end_at > now();

  if not found then
    raise exception using errcode = 'P0001',
      message = 'Varausta ei voitu poistaa: se on jo poistettu tai päättynyt.';
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;
