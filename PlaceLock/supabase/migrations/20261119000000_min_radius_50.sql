-- Places can be as small as 50 m (was 100 m). The app warns below 100 m that small circles can
-- miss arrivals indoors, where iOS's background location is often off by 20-65 m.
alter table public.places drop constraint places_radius_m_check;
alter table public.places add constraint places_radius_m_check check (radius_m between 50 and 500);

alter table public.places drop constraint places_pending_radius_m_check;
alter table public.places add constraint places_pending_radius_m_check
  check (pending_radius_m between 50 and 500);
