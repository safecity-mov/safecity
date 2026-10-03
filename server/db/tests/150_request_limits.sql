-- L'application — délai maximal par requête, par rôle (0180).
BEGIN;
SELECT no_plan();

SELECT is((SELECT array_to_string(s.setconfig, ',') FROM pg_db_role_setting s
            WHERE s.setrole = 'anon'::regrole AND s.setdatabase = 0),
          'statement_timeout=5s',
          'une requête anonyme est coupée au bout de cinq secondes');
SELECT is((SELECT array_to_string(s.setconfig, ',') FROM pg_db_role_setting s
            WHERE s.setrole = 'admin_api'::regrole AND s.setdatabase = 0),
          'statement_timeout=15s',
          'une action d''administration a droit à quinze secondes');

SELECT * FROM finish();
ROLLBACK;
