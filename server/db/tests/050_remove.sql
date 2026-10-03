-- L'application — §6.1 retrait par le créateur sous 24 h. C'est ce qui justifie de garder
-- min_resolve_votes à 2 plutôt que 1 (§0) : l'erreur de bonne foi a déjà son chemin.
BEGIN;
SELECT no_plan();

CREATE TEMP TABLE h (label text PRIMARY KEY, id uuid);
CREATE TEMP TABLE d (label text PRIMARY KEY, id uuid DEFAULT gen_random_uuid());
INSERT INTO d (label) VALUES ('auteur'), ('autre');

INSERT INTO h VALUES ('frais', app_test.report((SELECT id FROM d WHERE label='auteur'), 48.8566, 2.3522));

-- Un tiers ne retire pas le signalement d'un autre.
SELECT throws_ok(
  format($$ SELECT remove_own_hazard(gen_random_uuid(), %L::uuid, %L::uuid) $$,
         (SELECT id FROM h WHERE label='frais'), (SELECT id FROM d WHERE label='autre')),
  '42501', NULL, 'seul le créateur peut retirer son propre signalement');
SELECT is(app_test.status((SELECT id FROM h WHERE label='frais')), 'active',
          'le danger est intact');

-- Le créateur, lui, le retire immédiatement.
SELECT lives_ok(
  format($$ SELECT remove_own_hazard(gen_random_uuid(), %L::uuid, %L::uuid) $$,
         (SELECT id FROM h WHERE label='frais'), (SELECT id FROM d WHERE label='auteur')),
  'le créateur retire son signalement');
SELECT is(app_test.status((SELECT id FROM h WHERE label='frais')), 'removed',
          'statut removed, immédiatement (§6.1)');
SELECT is((SELECT count(*) FROM hazards WHERE id = (SELECT id FROM h WHERE label='frais')), 1::bigint,
          'aucune suppression physique : tout reste en base (§5)');
SELECT is((SELECT count(*) FROM events e
            WHERE e.hazard_id = (SELECT id FROM h WHERE label='frais') AND e.type = 'remove'),
          1::bigint, 'et le retrait est tracé dans le journal');

-- Un danger retiré sort de la carte et n'accepte plus de vote.
SELECT is((SELECT jsonb_array_length(hazards_in_bbox(2.34, 48.85, 2.36, 48.87) -> 'features')),
          0, 'il disparaît des résultats de la carte');
-- Et la réponse dit qu'elle est complète : sans ce drapeau, l'app ne peut pas distinguer
-- « la zone est vide » de « je n'ai pas tout renvoyé » (AUDIT M11).
SELECT is((hazards_in_bbox(2.34, 48.85, 2.36, 48.87) ->> 'truncated')::boolean, false,
          'une réponse qui tient sous le plafond se déclare complète');
SELECT throws_ok(
  format($$ SELECT app_test.confirm_near(gen_random_uuid(), %L::uuid) $$,
         (SELECT id FROM h WHERE label='frais')),
  '23514', NULL, 'un danger retiré n''est plus confirmable');
SELECT throws_ok(
  format($$ SELECT app_test.resolve_near(gen_random_uuid(), %L::uuid) $$,
         (SELECT id FROM h WHERE label='frais')),
  '23514', NULL, 'ni marquable résolu');
SELECT ok(hazard_detail((SELECT id FROM h WHERE label='frais')) IS NULL,
          'et son détail n''est plus servi');

-- Retirer deux fois est sans effet et sans erreur (rejeu hors-ligne, §10).
SELECT lives_ok(
  format($$ SELECT remove_own_hazard(gen_random_uuid(), %L::uuid, %L::uuid) $$,
         (SELECT id FROM h WHERE label='frais'), (SELECT id FROM d WHERE label='auteur')),
  'retirer un danger déjà retiré ne lève pas d''erreur');

-- --- Au-delà de 24 h, la porte est fermée -------------------------------------------
INSERT INTO h VALUES ('vieux', app_test.report((SELECT id FROM d WHERE label='auteur'), 48.8600, 2.3600));
UPDATE hazards SET created_at = now() - interval '25 hours'
 WHERE id = (SELECT id FROM h WHERE label='vieux');

SELECT throws_ok(
  format($$ SELECT remove_own_hazard(gen_random_uuid(), %L::uuid, %L::uuid) $$,
         (SELECT id FROM h WHERE label='vieux'), (SELECT id FROM d WHERE label='auteur')),
  '23514', NULL, 'passé 24 h, le créateur doit passer par le vote « résolu » (§6.1)');
SELECT is(app_test.status((SELECT id FROM h WHERE label='vieux')), 'active',
          'le danger reste sur la carte');

-- À 23 h, elle est encore ouverte.
UPDATE hazards SET created_at = now() - interval '23 hours'
 WHERE id = (SELECT id FROM h WHERE label='vieux');
SELECT lives_ok(
  format($$ SELECT remove_own_hazard(gen_random_uuid(), %L::uuid, %L::uuid) $$,
         (SELECT id FROM h WHERE label='vieux'), (SELECT id FROM d WHERE label='auteur')),
  'à 23 h, le retrait est encore possible');

-- --- D4 : un danger résolu quitte la carte, et toutes les portes disent la même chose --
INSERT INTO h VALUES ('bouche', app_test.report((SELECT id FROM d WHERE label='auteur'), 48.8650, 2.3650));
SELECT app_test.resolve_near(gen_random_uuid(), (SELECT id FROM h WHERE label='bouche'));
SELECT app_test.resolve_near(gen_random_uuid(), (SELECT id FROM h WHERE label='bouche'));
SELECT is(app_test.status((SELECT id FROM h WHERE label='bouche')), 'resolved',
          'le trou est rebouché : deux votes sur place le résolvent');

SELECT is((SELECT jsonb_array_length(hazards_in_bbox(2.36, 48.86, 2.37, 48.87) -> 'features')),
          0, 'il sort de la carte, sans calque ni option pour l''y ramener (AUDIT D4)');
SELECT hasnt_function('public', 'hazards_in_bbox',
                      ARRAY['double precision', 'double precision', 'double precision',
                            'double precision', 'text[]', 'smallint', 'boolean'],
                      'et le paramètre include_resolved n''existe plus');
SELECT is((SELECT count(*) FROM hazards_public p WHERE p.id = (SELECT id FROM h WHERE label='bouche')),
          0::bigint, 'la vue publique dit la même chose que la carte');
SELECT is(app_test.anon_sees((SELECT id FROM h WHERE label='bouche')), 0::bigint,
          'et la policy aussi : anon ne lit plus un danger résolu');

-- Le cycle se referme sans lui : l'anti-doublon ne regarde que les dangers encore visibles,
-- donc le jour où le trou se rouvre, le signalement suivant crée un danger neuf.
SELECT isnt((app_test.report(gen_random_uuid(), 48.8650, 2.3650))::text,
            ((SELECT id FROM h WHERE label='bouche'))::text,
            'un nouveau signalement au même endroit n''est pas rattaché au danger résolu');

SELECT * FROM finish();
ROLLBACK;
