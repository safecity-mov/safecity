import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/src/data/announcements.dart';
import 'package:app/src/data/api_client.dart';

/// Les annonces de l'équipe (§4.3 amendé) : lues sans rien envoyer, jamais une
/// panne quand le serveur se tait, et ce qu'on a fermé reste fermé.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const active = {
    'id': 7,
    'body': '  Les signalements du 21 au 27/09 ont été perdus : merci de les refaire.  ',
    'ends_at': '2099-01-01T00:00:00+00:00',
  };

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  AnnouncementChecker checker(_Reply reply) => AnnouncementChecker(
        api: ApiClient(httpClient: _FakeClient(reply), baseUrl: 'https://exemple.org/rest/v1'),
        storage: const FlutterSecureStorage(),
      );

  test('rapporte l\'annonce en cours, texte débarrassé de ses espaces', () async {
    final result = await checker(_Reply.json([active])).check();
    expect(result, isA<Announced>());
    final announcement = (result as Announced).announcement;
    expect(announcement.id, 7);
    expect(announcement.body, 'Les signalements du 21 au 27/09 ont été perdus : merci de les refaire.');
    expect(announcement.endsAt.year, 2099);
  });

  test('la requête ne porte rien : ni en-tête à nous, ni corps', () async {
    final client = _FakeClient(_Reply.json([active]));
    await AnnouncementChecker(
      api: ApiClient(httpClient: client, baseUrl: 'https://exemple.org/rest/v1'),
      storage: const FlutterSecureStorage(),
    ).check();
    final request = client.lastRequest!;
    expect(request.method, 'GET');
    expect(request.url.host, 'exemple.org');
    expect(request.url.path, '/rest/v1/announcements_public');
    expect(request.contentLength ?? 0, 0);
    expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-device-id')));
  });

  test('« rien d\'annoncé » quand la vue est vide', () async {
    expect(await checker(_Reply.json([])).check(), isA<NothingAnnounced>());
  });

  test('« injoignable » sans réseau, sur une erreur ou un contenu illisible', () async {
    expect(await checker(_Reply.offline()).check(), isA<AnnouncementsUnavailable>());
    expect(await checker(_Reply.status(500)).check(), isA<AnnouncementsUnavailable>());
    expect(await checker(_Reply.text('pas du json')).check(), isA<AnnouncementsUnavailable>());
    expect(await checker(_Reply.json([{'id': 'x'}])).check(), isA<AnnouncementsUnavailable>());
  });

  test('une annonce fermée ne revient pas, une autre si', () async {
    final c = checker(_Reply.json([active]));
    final first = await c.check() as Announced;
    await c.dismiss(first.announcement);

    expect(await c.check(), isA<NothingAnnounced>(), reason: 'même annonce : déjà lue');

    final other = checker(_Reply.json([{...active, 'id': 8, 'body': 'Autre chose.'}]));
    final result = await other.check();
    expect(result, isA<Announced>());
    expect((result as Announced).announcement.body, 'Autre chose.');
  });

  test('coupe un texte que le serveur aurait laissé passer trop long', () {
    final a = Announcement.fromJson({
      'id': 1,
      'body': 'x' * 300,
      'ends_at': '2099-01-01T00:00:00Z',
    });
    expect(a.body.length, Announcement.maxLength);
  });
}

class _Reply {
  _Reply(this.status, this.body, {this.offline = false});

  factory _Reply.json(Object body) => _Reply(200, jsonEncode(body));
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
