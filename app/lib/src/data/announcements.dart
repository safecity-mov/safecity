import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

/// Une annonce écrite depuis la console (§4.3 amendé), telle que le serveur la
/// publie dans `announcements_public` : une ligne, et jusqu'à quand.
///
/// Rien ici ne dit qui l'a écrite, ni à qui elle s'adresse : c'est le même
/// texte pour tout le monde.
class Announcement {
  const Announcement({required this.id, required this.body, required this.endsAt});

  final int id;
  final String body;
  final DateTime endsAt;

  /// Le serveur borne déjà à 200 caractères ; on ne fait pas confiance à une
  /// réponse pour dimensionner un bandeau, on coupe aussi ici.
  static const maxLength = 200;

  factory Announcement.fromJson(Map<String, dynamic> json) {
    final body = (json['body'] as String).trim();
    return Announcement(
      id: json['id'] as int,
      body: body.length > maxLength ? body.substring(0, maxLength) : body,
      endsAt: DateTime.parse(json['ends_at'] as String),
    );
  }
}

/// Ce que le serveur a répondu, sans rien lever.
///
/// Trois cas, parce que la carte ne réagit pas pareil : une annonce s'affiche,
/// « rien d'annoncé » efface celle qu'on montrait (elle a été retirée ou a pris
/// fin), et un serveur injoignable ne change rien à l'écran — une annonce ne
/// disparaît pas parce que le réseau a sauté.
sealed class AnnouncementCheck {
  const AnnouncementCheck();
}

final class Announced extends AnnouncementCheck {
  const Announced(this.announcement);
  final Announcement announcement;
}

final class NothingAnnounced extends AnnouncementCheck {
  const NothingAnnounced();
}

final class AnnouncementsUnavailable extends AnnouncementCheck {
  const AnnouncementsUnavailable();
}

/// Demande au serveur s'il y a quelque chose à dire, et retient ce qu'on a déjà lu.
///
/// Mêmes moments que la vérification de mise à jour — lancement et retour au
/// premier plan — et même discrétion : une requête GET sans en-tête ni corps,
/// vers notre serveur seulement (§11.5). Ne lève jamais.
///
/// Toucher le bandeau ferme l'annonce, et on s'en souvient : l'identifiant de
/// la dernière annonce fermée est gardé en stockage local, comme `onboarding_done`.
/// Un entier qui ne dit rien de la personne, et qui évite de rappeler dix fois ce
/// qui a été lu. Une autre annonce, autre identifiant, s'affiche à son tour.
class AnnouncementChecker {
  AnnouncementChecker({required ApiClient api, FlutterSecureStorage? storage})
      : _api = api,
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final ApiClient _api;
  final FlutterSecureStorage _storage;

  static const _dismissedKey = 'announcement_dismissed_id';

  Future<AnnouncementCheck> check() async {
    final Announcement? current;
    try {
      current = await _api.fetchAnnouncement();
    } on Object {
      return const AnnouncementsUnavailable();
    }
    if (current == null) return const NothingAnnounced();

    final dismissed = await _readDismissed();
    if (dismissed == current.id) return const NothingAnnounced();
    return Announced(current);
  }

  Future<void> dismiss(Announcement announcement) async {
    try {
      await _storage.write(key: _dismissedKey, value: '${announcement.id}');
    } on Object {
      // Le stockage qui refuse d'écrire ne doit pas empêcher de fermer le
      // bandeau : au pire, il reviendra au prochain lancement.
    }
  }

  Future<int?> _readDismissed() async {
    try {
      return int.tryParse(await _storage.read(key: _dismissedKey) ?? '');
    } on Object {
      return null;
    }
  }
}
