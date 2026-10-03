import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Identité anonyme du terminal (§0, §11.2).
///
/// Un UUID aléatoire, généré sur l'appareil, gardé en stockage chiffré. C'est la
/// seule identité du système : pas de compte, pas d'e-mail, pas d'identifiant
/// publicitaire, pas d'empreinte d'appareil. Il sert à deux choses et rien
/// d'autre : empêcher un même terminal de voter deux fois sur un danger, et
/// permettre à un auteur de retirer son signalement dans les 24 h.
class DeviceIdentity {
  DeviceIdentity({FlutterSecureStorage? storage, Uuid? uuid})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _uuid = uuid ?? const Uuid();

  static const _key = 'device_id';

  final FlutterSecureStorage _storage;
  final Uuid _uuid;
  String? _cached;

  Future<String> get id async {
    final cached = _cached;
    if (cached != null) return cached;

    final stored = await _storage.read(key: _key);
    if (stored != null) {
      _cached = stored;
      return stored;
    }

    final fresh = _uuid.v4();
    await _storage.write(key: _key, value: fresh);
    _cached = fresh;
    return fresh;
  }

  /// « Régénérer mon identifiant » (§11.4).
  ///
  /// Coupe le lien avec toutes les actions passées, immédiatement et sans rien
  /// demander à personne. Les signalements restent : ce sont des données sur la
  /// voirie, pas sur la personne.
  Future<String> regenerate() async {
    final fresh = _uuid.v4();
    await _storage.write(key: _key, value: fresh);
    _cached = fresh;
    return fresh;
  }

  /// Identifiant d'une action, distinct du terminal.
  ///
  /// Chaque écriture en porte un : rejouer une action mise en file d'attente hors
  /// ligne ne crée jamais de doublon côté serveur (§8, §10). La file vit en
  /// mémoire, dans `HazardRepository` ; cet identifiant est ce qui rend son
  /// rejeu sûr.
  String newClientId() => _uuid.v4();
}
