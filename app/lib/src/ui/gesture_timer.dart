/// Le chronomètre de la mesure n°1 du §4.6 : « un signalement tient-il sous
/// quinze secondes ? ».
///
/// Il vit à part parce que sa règle tient en quatre lignes et que rien ne la
/// vérifiait. Un `Stopwatch` nu, démarré à l'entrée en mode placement et jamais
/// annulé, donnait deux mesures fausses : annuler un placement puis rouler dix
/// minutes avant d'en refaire un enregistrait six cents secondes pour un geste
/// qui en avait pris quinze, et un placement ouvert par un tap direct sur la
/// carte n'était pas mesuré du tout.
///
/// La mesure sert à décider si le produit tient sa promesse. Une mesure fausse
/// est pire qu'une mesure absente : elle se lit comme une réponse.
class GestureTimer {
  Stopwatch? _clock;

  /// Un geste commence. Redémarre depuis zéro : repasser en mode placement,
  /// c'est recommencer, pas continuer.
  void start() => _clock = Stopwatch()..start();

  /// Le geste est abandonné. Ce qui viendra après ne lui doit rien.
  void cancel() => _clock = null;

  /// Le geste a abouti : rend sa durée, et une seule fois.
  ///
  /// `null` quand aucun geste n'était en cours. Un signalement arrivé par un
  /// chemin qu'on n'a pas instrumenté ne doit pas hériter du chronomètre d'un
  /// autre : mieux vaut ne rien relever.
  Duration? take() {
    final elapsed = _clock?.elapsed;
    _clock = null;
    return elapsed;
  }

  /// Vrai tant qu'un geste est en cours de mesure.
  bool get running => _clock != null;
}
