/// Les seuils de résolution du §6.1, tels que le serveur les publie.
///
/// L'app ne décide de rien : elle les affiche. Un signalement qui n'est pas encore
/// parti doit pouvoir annoncer « 1 vote sur 2 » sans attendre la réponse du serveur,
/// et deux versions de l'app installées en même temps doivent dire la même chose —
/// d'où une règle lue, comme les paliers de proximité (§6.2), et non compilée.
class ModerationRules {
  const ModerationRules({required this.minResolveVotes});

  /// Ce que dit le §0 tant que le serveur n'a rien dit. Un geste doit pouvoir
  /// partir, et un marqueur s'afficher, même au tout premier lancement hors ligne.
  static const fallback = ModerationRules(minResolveVotes: 2);

  /// Le plancher du seuil : ce qu'il faut de voix « résolu » sur un danger neuf.
  ///
  /// Les deux autres réglages — le rythme et le plafond — ne servent qu'au-delà de
  /// la première confirmation, que l'app n'a par définition pas encore vue sur un
  /// signalement qu'elle vient de créer. Le serveur les applique, elle non.
  final int minResolveVotes;

  /// PostgREST rend une liste d'une ligne : la table n'en a qu'une.
  factory ModerationRules.fromJson(List<dynamic> rows) {
    if (rows.isEmpty) return fallback;
    final row = rows.first as Map<String, dynamic>;
    return ModerationRules(minResolveVotes: row['min_resolve_votes'] as int);
  }
}
