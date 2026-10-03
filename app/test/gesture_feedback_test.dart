import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/data/models/hazard.dart';
import 'package:app/src/data/models/hazard_type.dart';
import 'package:app/src/data/models/severity.dart';
import 'package:app/src/ui/gesture_feedback.dart';
import 'package:app/src/ui/hazard_detail_sheet.dart';
import 'package:app/src/ui/labels.dart';

void main() {
  group('feedbackFor', () {
    test('un vote « résolu » sous le quorum le dit au lieu de laisser croire à un échec', () {
      // §6.1 : le vote est pris, le danger reste sur la carte. Annoncer « réparé »
      // serait faux, ne rien dire ferait croire que le geste n'est pas passé.
      final message = feedbackFor(
        DetailAction.resolve,
        _hazard(status: HazardStatus.disputed),
        _pothole,
      );

      expect(message, MapLabels.voteRecorded);
    });

    test('un vote qui fait basculer emprunte le verbe du type', () {
      // Le verbe vient du catalogue, jamais d'un libellé en dur (§3).
      expect(
        feedbackFor(DetailAction.resolve, _hazard(status: HazardStatus.resolved), _pothole),
        MapLabels.markedResolved(_pothole.resolvedLabel.toLowerCase()),
      );
      expect(
        feedbackFor(DetailAction.resolve, _hazard(status: HazardStatus.resolved), _debris),
        MapLabels.markedResolved(_debris.resolvedLabel.toLowerCase()),
      );
    });

    test('confirmer et retirer ont leur propre retour', () {
      expect(feedbackFor(DetailAction.confirm, _hazard(), _pothole), MapLabels.confirmed);
      expect(feedbackFor(DetailAction.removeOwn, _hazard(), _pothole), MapLabels.removed);
    });
  });

  group('withoutPosition', () {
    test('dit que le geste pèse moins', () {
      // §6.2 : sans position il vaut 0,25 au lieu de 1. Le taire laisserait croire
      // qu'on pèse autant qu'un geste fait sur place (§4.6).
      const base = MapLabels.reportSent;
      final message = withoutPosition(base, permissionDenied: false);

      expect(message, startsWith(base));
      expect(message, MapLabels.weakerWithoutPosition(base));
    });

    test('et conseille autre chose quand c\'est la permission qui manque', () {
      // Deux causes, deux conseils : sans signal on n'y peut rien, tandis qu'une
      // autorisation « une seule fois » se redonne « pendant l'utilisation ».
      const base = MapLabels.reportSent;
      final denied = withoutPosition(base, permissionDenied: true);

      expect(denied, MapLabels.weakerWithoutPermission(base));
      expect(denied, isNot(MapLabels.weakerWithoutPosition(base)));
    });
  });

  group('distanceLabel', () {
    test('« au même endroit » plutôt que « à 0 m »', () {
      // Le pin est posé à la main : tomber à moins d'un mètre est le cas courant.
      expect(distanceLabel(0.4), MapLabels.sameSpot);
    });

    test('arrondit au mètre au-delà', () {
      expect(distanceLabel(8.4), MapLabels.atDistance(8));
      expect(distanceLabel(8.6), MapLabels.atDistance(9));
    });
  });

  group('relativeDateShort', () {
    final now = DateTime(2026, 9, 15, 12);

    test('nomme aujourd\'hui et hier', () {
      expect(relativeDateShort(DateTime(2026, 9, 15, 8), now: now), MapLabels.today);
      expect(relativeDateShort(DateTime(2026, 9, 14, 8), now: now), MapLabels.yesterday);
    });

    test('compte les jours ensuite', () {
      expect(relativeDateShort(DateTime(2026, 9, 10, 8), now: now), MapLabels.daysAgo(5));
    });
  });
}

Hazard _hazard({HazardStatus status = HazardStatus.active}) => Hazard(
      id: 'h',
      type: 'pothole',
      lat: 48.85,
      lng: 2.35,
      severity: Severity.fromValue(2),
      status: status,
      createdAt: DateTime(2026, 9, 13),
      lastConfirmedAt: DateTime(2026, 9, 13),
      confirmWeight: 3,
      resolveWeight: 0,
      resolveThreshold: 2,
      reportedRemotely: false,
    );

const _pothole = HazardType(
  code: 'pothole',
  label: 'Nid-de-poule',
  iconName: 'pothole',
  resolvedLabel: 'Réparé',
  dedupRadiusM: 15,
  enabled: true,
  sortOrder: 10,
);

const _debris = HazardType(
  code: 'debris',
  label: 'Verre brisé, gravats, débris',
  iconName: 'debris',
  resolvedLabel: 'Nettoyé',
  dedupRadiusM: 15,
  enabled: true,
  sortOrder: 40,
);
