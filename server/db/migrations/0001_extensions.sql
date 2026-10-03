-- L'application — extensions requises.
-- PostGIS : géométrie des dangers (§5, §11.6 — pleine précision, aucun arrondi).
CREATE EXTENSION IF NOT EXISTS postgis;

-- pg_cron : uniquement pour la coupure du lien terminal → gestes à 24 heures (§11.2, 0050).
-- Le cron d'expiration des dangers (§6.4) est reporté en phase 2 (§4.6) et n'est pas planifié ici.
-- Nécessite shared_preload_libraries = 'pg_cron' et cron.database_name = <base> (voir docker-compose.yml).
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron indisponible (%), l''anonymisation devra être déclenchée manuellement', SQLERRM;
END
$$;
