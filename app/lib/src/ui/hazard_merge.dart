import '../data/models/hazard.dart';

/// Une étendue géographique, telle que la carte la donne.
typedef Bbox = ({double minLat, double minLng, double maxLat, double maxLng});

/// Ce que la carte doit afficher après qu'une zone a répondu.
///
/// On fusionne plutôt que de remplacer — repasser sur une zone déjà vue ne doit
/// pas faire clignoter les marqueurs — mais une fusion qui n'oublie jamais rien
/// fabrique des fantômes : un danger retiré par la console ou résolu par
/// d'autres restait affiché « actif » toute la session, et un signalement
/// provisoire, une fois envoyé sous son vrai identifiant, restait dessiné une
/// seconde fois sous son identifiant provisoire, sans qu'on puisse l'ouvrir.
///
/// La règle : quand la réponse **vient du serveur** ([authoritative]), tout ce
/// qui était affiché dans la zone et n'y figure plus disparaît. Les signalements
/// encore en file font partie de la réponse — le dépôt les y ajoute — et
/// survivent donc ; ceux que la file a envoyés n'en font plus partie, et c'est
/// bien ce qu'on veut. Une réponse du cache ne fait pas foi : elle ne retire rien.
///
/// Fonction pure, sans la carte : c'est ce qui la rend testable.
Map<String, Hazard> mergeHazards({
  required Map<String, Hazard> current,
  required Iterable<Hazard> fetched,
  required Bbox bbox,
  required bool authoritative,
}) {
  final merged = Map<String, Hazard>.of(current);
  if (authoritative) {
    final kept = {for (final h in fetched) h.id};
    merged.removeWhere((id, h) => !kept.contains(id) && _within(h, bbox));
  }
  for (final h in fetched) {
    merged[h.id] = h;
  }
  return merged;
}

bool _within(Hazard h, Bbox b) =>
    h.lat >= b.minLat && h.lat <= b.maxLat && h.lng >= b.minLng && h.lng <= b.maxLng;
