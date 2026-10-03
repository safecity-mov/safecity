import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app/src/data/api_client.dart';
import 'package:app/src/data/moderation.dart';
import 'package:app/src/data/models/hazard.dart';

void main() {
  group('reportHazard', () {
    test('distingue un danger créé d\'un doublon proposé', () async {
      // §4.1 F2b : le serveur répond l'un ou l'autre, jamais les deux. C'est lui
      // qui décide s'il y a doublon, pas le client.
      final created = await _clientReturning(_hazardJson()).reportHazard(
        clientId: 'c',
        deviceId: 'd',
        type: 'pothole',
        lat: 48.8566,
        lng: 2.3522,
        severity: 2,
        proximity: 3,
      );
      expect(created, isA<HazardCreated>());

      final duplicate = await _clientReturning({
        'duplicate_of': '22222222-2222-2222-2222-222222222222',
        'distance_m': 5.6,
        'hazard': _hazardJson(),
      }).reportHazard(
        clientId: 'c',
        deviceId: 'd',
        type: 'pothole',
        lat: 48.8566,
        lng: 2.3522,
        severity: 2,
        proximity: 3,
      );

      expect(duplicate, isA<DuplicateFound>());
      expect((duplicate as DuplicateFound).distanceM, 5.6);
    });

    test('n\'envoie la position du terminal que si elle est connue', () async {
      // Refuser la localisation reste un usage possible : l'action part quand
      // même, elle pèsera 0,25 côté serveur (§6.2).
      late Map<String, dynamic> sent;
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_hazardJson()), 200);
        }),
      );

      await client.reportHazard(
        clientId: 'c',
        deviceId: 'd',
        type: 'pothole',
        lat: 48.8566,
        lng: 2.3522,
        severity: 2,
        proximity: 3,
      );

      expect(sent.containsKey('device_lat'), isFalse);
      expect(sent.containsKey('device_lng'), isFalse);
      expect(sent['proximity'], 3);
    });

    test('transmet le palier, et rien qui ressemble à une position', () async {
      // Le palier est calculé sur l'appareil : la position du déclarant ne quitte
      // jamais le téléphone (§6.2, §11.1).
      late Map<String, dynamic> sent;
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_hazardJson()), 200);
        }),
      );

      await client.reportHazard(
        clientId: 'c',
        deviceId: 'd',
        type: 'pothole',
        lat: 48.8566,
        lng: 2.3522,
        severity: 2,
        proximity: 1,
      );

      expect(sent['proximity'], 1);
    });

    test('omet un commentaire vide plutôt que d\'envoyer une chaîne vide', () async {
      late Map<String, dynamic> sent;
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_hazardJson()), 200);
        }),
      );

      await client.reportHazard(
        clientId: 'c',
        deviceId: 'd',
        type: 'pothole',
        lat: 48.8566,
        lng: 2.3522,
        severity: 2,
        description: '',
        proximity: 3,
      );

      expect(sent.containsKey('description'), isFalse);
    });
  });

  group('erreurs', () {
    test('remonte le message du serveur, déjà écrit en français', () async {
      // Les RPC lèvent des exceptions lisibles (§8) : les réécrire côté client
      // ferait diverger deux formulations de la même règle.
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        // http.Response(String) encode en latin1 : aucun serveur réel ne fait
        // ça, PostgREST répond en UTF-8.
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'message': 'délai de retrait de 24 h dépassé'})),
            400,
          ),
        ),
      );

      final message = isA<ApiException>().having(
        (e) => e.message,
        'message',
        contains('24 h'),
      );

      expect(
        () => client.removeOwnHazard(clientId: 'c', deviceId: 'd', hazardId: 'h'),
        throwsA(message),
      );
    });

    test('reste lisible quand le corps n\'est pas du JSON', () async {
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        httpClient: MockClient((_) async => http.Response('<html>502</html>', 502)),
      );

      final status = isA<ApiException>().having(
        (e) => e.statusCode,
        'statusCode',
        502,
      );

      expect(() => client.fetchTypes(), throwsA(status));
    });
  });

  group('hazardsInBbox', () {
    test('n\'envoie un filtre que lorsqu\'il est posé', () async {
      late Map<String, dynamic> sent;
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'type': 'FeatureCollection', 'features': []}),
            200,
          );
        }),
      );

      await client.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);

      expect(sent.containsKey('types'), isFalse);
      expect(sent.containsKey('min_severity'), isFalse);
      expect(sent.containsKey('include_resolved'), isFalse);
    });

    test('rapporte que le serveur a coupé', () async {
      // Au-delà de son plafond, le serveur ne décrit plus la zone entière : le
      // client doit le savoir pour ne rien déduire de ce qui manque (§10).
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'type': 'FeatureCollection',
              'truncated': true,
              'features': <dynamic>[],
            }),
            200,
          ),
        ),
      );

      final result =
          await client.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);

      expect(result.truncated, isTrue);
    });

    test('décode une FeatureCollection vide sans erreur', () async {
      // La carte démarre vide (§4.4) : c'est le cas nominal au lancement.
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'type': 'FeatureCollection', 'features': []}),
            200,
          ),
        ),
      );

      final result =
          await client.hazardsInBbox(minLng: 2.3, minLat: 48.8, maxLng: 2.4, maxLat: 48.9);

      expect(result.hazards, isEmpty);
      // Un serveur qui ne dit rien de la troncature est réputé complet : c'est le
      // comportement d'avant, et il ne doit pas rendre la carte aveugle.
      expect(result.truncated, isFalse);
    });
  });

  test('hazardDetail rend null pour un danger masqué', () async {
    // Le serveur ne sert pas le détail d'un danger retiré ou archivé.
    final client = ApiClient(
      baseUrl: 'http://test/rest/v1',
      httpClient: MockClient((_) async => http.Response('null', 200)),
    );

    expect(await client.hazardDetail('h'), isNull);
  });

  group('fetchModerationRules', () {
    test('lit le plancher publié par le serveur', () async {
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {'min_resolve_votes': 4},
            ]),
            200,
          ),
        ),
      );

      expect((await client.fetchModerationRules()).minResolveVotes, 4);
    });

    test('retombe sur la règle compilée si la table est vide', () async {
      // Une base sans sa ligne de réglages ne doit pas rendre l'app inutilisable :
      // le serveur tranchera de toute façon au moment du geste (§6.1).
      final client = ApiClient(
        baseUrl: 'http://test/rest/v1',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );

      expect(
        (await client.fetchModerationRules()).minResolveVotes,
        ModerationRules.fallback.minResolveVotes,
      );
    });
  });
}

ApiClient _clientReturning(Map<String, dynamic> body) => ApiClient(
      baseUrl: 'http://test/rest/v1',
      httpClient: MockClient((_) async => http.Response(jsonEncode(body), 200)),
    );

Map<String, dynamic> _hazardJson() => {
      'id': '11111111-1111-1111-1111-111111111111',
      'type': 'pothole',
      'lat': 48.8566,
      'lng': 2.3522,
      'severity': 2,
      'status': 'active',
      'description': null,
      'address': null,
      'created_at': '2026-09-13T22:00:00+00:00',
      'last_confirmed_at': '2026-09-13T22:30:00+00:00',
      'resolve_weight': 0.0,
      'resolve_threshold': 2,
      'reported_remotely': false,
    };
