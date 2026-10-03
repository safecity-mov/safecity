import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/src/data/app_update.dart';

/// La vérification de mise à jour ne doit jamais gêner : ni casser l'app
/// quand le serveur répond mal, ni la renvoyer ailleurs que chez lui.
void main() {
  const latest = {
    'package': 'me.safe',
    'versionName': '0.2.0',
    'versionCode': 3,
    'url': 'https://exemple.org/fdroid/app-latest.apk',
    'sha256': 'abc',
    'size': 12345,
    'minVersionCode': 0,
    'note': '',
  };

  UpdateChecker checker(_Reply reply, {int installed = 1}) => UpdateChecker(
        httpClient: _FakeClient(reply),
        url: 'https://exemple.org/fdroid/latest.json',
        installedCode: installed,
      );

  group('UpdateChecker', () {
    test('annonce une version plus récente', () async {
      final update = await checker(_Reply.json(latest)).check();
      expect(update, isNotNull);
      expect(update!.versionName, '0.2.0');
      expect(update.versionCode, 3);
      expect(update.isRequiredFor(1), isFalse);
    });

    test('se tait quand la version installée est la dernière', () async {
      expect(await checker(_Reply.json(latest), installed: 3).check(), isNull);
      expect(await checker(_Reply.json(latest), installed: 4).check(), isNull);
    });

    test('la requête ne porte rien : ni en-tête à nous, ni corps', () async {
      final client = _FakeClient(_Reply.json(latest));
      await UpdateChecker(
        httpClient: client,
        url: 'https://exemple.org/fdroid/latest.json',
        installedCode: 1,
      ).check();
      final request = client.lastRequest!;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://exemple.org/fdroid/latest.json');
      expect(request.contentLength ?? 0, 0);
      expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-device-id')));
    });

    test('refuse un APK hébergé sur un autre domaine', () async {
      // Le serveur ne peut pas envoyer l'app ailleurs que chez lui, même s'il
      // le demande : c'est la promesse « un seul domaine » du §11.5.
      final ailleurs = {...latest, 'url': 'https://autre.example/app.apk'};
      expect(await checker(_Reply.json(ailleurs)).check(), isNull);
      final clair = {...latest, 'url': 'http://exemple.org/fdroid/app-latest.apk'};
      expect(await checker(_Reply.json(clair)).check(), isNull);
    });

    test('ne lève jamais : 404, contenu illisible, réseau coupé', () async {
      expect(await checker(_Reply.status(404)).check(), isNull);
      expect(await checker(_Reply.status(500)).check(), isNull);
      expect(await checker(_Reply.text('<html>pas du json')).check(), isNull);
      expect(await checker(_Reply.json({'versionName': '0.2.0'})).check(), isNull);
      expect(await checker(_Reply.offline()).check(), isNull);
    });

    test('lit la version minimale exigée', () async {
      final exige = {...latest, 'minVersionCode': 3};
      final update = await checker(_Reply.json(exige)).check();
      expect(update!.isRequiredFor(1), isTrue);
      expect(update.isRequiredFor(3), isFalse);
    });
  });
}

class _Reply {
  _Reply(this.status, this.body, {this.offline = false});

  factory _Reply.json(Map<String, dynamic> body) => _Reply(200, jsonEncode(body));
  factory _Reply.text(String body) => _Reply(200, body);
  factory _Reply.status(int status) => _Reply(status, '');
  factory _Reply.offline() => _Reply(0, '', offline: true);

  final int status;
  final String body;
  final bool offline;
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.reply);

  final _Reply reply;
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (reply.offline) throw const SocketException('réseau coupé');
    return http.StreamedResponse(
      Stream.value(utf8.encode(reply.body)),
      reply.status,
      headers: const {'content-type': 'application/json'},
    );
  }
}
