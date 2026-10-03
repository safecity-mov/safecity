import '../data/models/hazard.dart';
import '../data/models/hazard_type.dart';
import 'hazard_detail_sheet.dart';
import 'labels.dart';

/// Ce que l'app répond après un geste : des fonctions pures, sorties de l'écran
/// carte pour pouvoir être lues et vérifiées sans monter une carte.
///
/// Elles décident de la seule chose que l'utilisateur verra d'un geste réussi.
/// Se tromper ici, c'est annoncer un danger effacé alors qu'il est seulement
/// contesté, ou taire qu'un geste a compté pour un quart.

/// Le retour d'un geste appliqué par le serveur.
///
/// Le statut vient du serveur, jamais d'une supposition du client (§10) : c'est
/// lui qui dit si le quorum du §6.1 est atteint.
String feedbackFor(DetailAction action, Hazard hazard, HazardType type) => switch (action) {
      DetailAction.confirm => MapLabels.confirmed,
      DetailAction.removeOwn => MapLabels.removed,
      DetailAction.resolve => switch (hazard.status) {
          HazardStatus.resolved => MapLabels.markedResolved(type.resolvedLabel.toLowerCase()),
          // Le vote a été enregistré mais le quorum n'est pas atteint : le dire,
          // plutôt que de laisser croire à un échec (§6.1).
          _ => MapLabels.voteRecorded,
        },
    };

/// Ce qu'on ajoute quand un geste est parti sans position.
///
/// Il vaut 0,25 au lieu de 1 (§6.2), et l'utilisateur doit le savoir : sans
/// cela il croit peser sur la carte alors qu'il pèse un quart, et c'est
/// précisément ce que la bêta cherche à mesurer (§4.6).
///
/// Deux causes très différentes, donc deux conseils. Pas de signal, on n'y peut
/// rien. Permission révoquée, si : une autorisation « une seule fois » est
/// retirée par Android à chaque passage en arrière-plan, donc le problème se
/// reproduira à chaque réveil tant qu'elle n'est pas donnée « pendant
/// l'utilisation ».
String withoutPosition(String base, {required bool permissionDenied}) => permissionDenied
    ? MapLabels.weakerWithoutPermission(base)
    : MapLabels.weakerWithoutPosition(base);

/// « au même endroit » plutôt que « à 0 m » : le pin est posé à la main, tomber
/// à moins d'un mètre du danger existant est le cas le plus courant.
String distanceLabel(double distanceM) =>
    distanceM < 1 ? MapLabels.sameSpot : MapLabels.atDistance(distanceM.round());

/// « aujourd'hui », « hier », « il y a 2 jours » — variante courte pour le
/// dialogue anti-doublon, qui doit tenir sur une ligne.
String relativeDateShort(DateTime date, {DateTime? now}) {
  final days = (now ?? DateTime.now()).difference(date).inDays;
  if (days == 0) return MapLabels.today;
  if (days == 1) return MapLabels.yesterday;
  return MapLabels.daysAgo(days);
}
