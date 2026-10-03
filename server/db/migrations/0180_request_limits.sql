-- L'application — 0180 : un délai maximal par requête, selon le rôle (§6.3 amendé).
--
-- Dix connexions dans le pool de PostgREST : dix guichets. Une requête qui traîne en occupe un
-- tant qu'elle dure, et dix requêtes qui traînent ferment l'API à tout le monde. Une requête
-- normale de l'app se compte en millisecondes ; cinq secondes, c'est cent fois plus, et
-- au-delà on préfère couper que laisser un guichet pris. Côté console, les actions qui
-- recalculent plusieurs dangers d'un coup — un bannissement — ont droit à plus.
--
-- Réglé sur le rôle emprunté, pas sur `authenticator` : PostgREST applique les réglages du
-- rôle qu'il endosse à chaque requête (« impersonated role settings », PostgREST ≥ 9). C'est
-- la voie documentée pour un `statement_timeout` par rôle. Aucun effet sur les migrations,
-- les tests ni `make psql`, qui tournent en `postgres`.
ALTER ROLE anon      SET statement_timeout = '5s';
ALTER ROLE admin_api SET statement_timeout = '15s';

NOTIFY pgrst, 'reload config';
