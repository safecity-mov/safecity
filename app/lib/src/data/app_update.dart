import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Ce que le serveur annonce comme dernière version publiée.
///
/// C'est le contenu de `latest.json`, écrit par `deploy/vps-publish.sh` à
/// chaque publication, à côté de la page de téléchargement. Rien ici ne vient
/// d'ailleurs que de notre propre serveur (§11.5).
class AppUpdate {
  const AppUpdate({
    required this.versionName,
    required this.versionCode,
    required this.url,
    required this.minVersionCode,
    required this.note,
  });

  final String versionName;
  final int versionCode;

  /// L'APK lui-même. Le navigateur le télécharge, Android propose l'installation
  /// par-dessus l'ancienne : même signature, donc données conservées.
  final Uri url;

  /// En dessous, la version installée ne doit plus servir : elle envoie quelque
  /// chose de faux, ou le serveur ne l'accepte plus. Zéro quand rien n'est exigé.
  final int minVersionCode;

  /// Une ligne libre, écrite au moment de publier. Souvent vide.
  final String note;

  factory AppUpdate.fromJson(Map<String, dynamic> json) => AppUpdate(
        versionName: json['versionName'] as String,
        versionCode: json['versionCode'] as int,
        url: Uri.parse(json['url'] as String),
        minVersionCode: (json['minVersionCode'] as int?) ?? 0,
        note: (json['note'] as String?) ?? '',
      );

  bool isNewerThan(int installedCode) => versionCode > installedCode;

  /// Une version installée sous le minimum exigé.
  bool isRequiredFor(int installedCode) => installedCode < minVersionCode;
}

/// Demande au serveur s'il existe une version plus récente que celle-ci.
///
/// Une seule requête GET, sans en-tête ni corps : ni l'identifiant de terminal,
/// ni la version installée ne partent. Le serveur n'apprend rien de plus que
/// pour une tuile de carte, et il ne journalise de toute façon pas (§11.5).
///
/// Ne lève jamais : une vérification de mise à jour qui échoue n'est pas une
/// panne de l'app. Sans réseau, sans fichier, ou devant un contenu illisible,
/// la réponse est simplement « rien à signaler ».
class UpdateChecker {
  UpdateChecker({
    http.Client? httpClient,
    String? url,
    int? installedCode,
  })  : _http = httpClient ?? http.Client(),
        _url = Uri.parse(url ?? AppConfig.updateUrl),
        _installedCode = installedCode ?? AppConfig.versionCode;

  final http.Client _http;
  final Uri _url;
  final int _installedCode;

  static const _timeout = Duration(seconds: 10);

  /// La mise à jour à proposer, ou `null` s'il n'y en a pas.
  ///
  /// C'est la question de la carte, qui n'a rien à dire quand il n'y a rien à
  /// installer, quelle qu'en soit la raison. L'écran Paramètres, lui, veut la
  /// nuance : il passe par [probe].
  Future<AppUpdate?> check() async => switch (await probe()) {
        UpdateAvailable(:final update) => update,
        _ => null,
      };

  /// Ce que le serveur a répondu, sans rien lever.
  ///
  /// Un `latest.json` qui annoncerait un APK hébergé ailleurs que sur notre
  /// domaine est traité comme illisible : l'app ne renvoie jamais vers un autre
  /// domaine, même sur ordre de son propre serveur (§11.5).
  Future<UpdateCheck> probe() async {
    try {
      final response = await _http.get(_url).timeout(_timeout);
      if (response.statusCode != 200) return const UpdateUnavailable();
      final update = AppUpdate.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      if (update.url.host != _url.host) return const UpdateUnavailable();
      if (update.url.scheme != _url.scheme) return const UpdateUnavailable();
      if (!update.isNewerThan(_installedCode)) return const UpToDate();
      return UpdateAvailable(update);
    } on Object {
      return const UpdateUnavailable();
    }
  }

  void dispose() => _http.close();
}

/// Résultat d'une vérification : à jour, plus récent disponible, ou pas de
/// réponse exploitable. Le troisième cas couvre aussi bien le réseau coupé que
/// le serveur qui n'a pas encore publié de `latest.json`.
sealed class UpdateCheck {
  const UpdateCheck();
}

final class UpToDate extends UpdateCheck {
  const UpToDate();
}

final class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(this.update);
  final AppUpdate update;
}

final class UpdateUnavailable extends UpdateCheck {
  const UpdateUnavailable();
}

/// Ouvre une adresse dans le navigateur du téléphone, par le canal natif.
///
/// Pas de `url_launcher` : un paquet de plus à justifier devant F-Droid
/// (§12.6) pour un `Intent.ACTION_VIEW` de trois lignes, et un manifeste
/// qu'il modifie par fusion. Le seul appelant est le bandeau de mise à jour,
/// et la seule adresse qu'il passe vient de `UpdateChecker`, qui l'a déjà
/// contrainte à notre domaine.
class ExternalLinks {
  const ExternalLinks();

  static const _channel = MethodChannel('me.safe/system');

  /// Vrai si une application a pris l'adresse en charge.
  Future<bool> open(Uri url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url.toString()}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
