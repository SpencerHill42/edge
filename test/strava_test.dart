// Strava sync: the pure pieces (lib/strava/strava.dart).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openstrap_edge/strava/strava.dart';
import 'package:openstrap_edge/strava/strava_sync.dart';

void main() {
  group('sport mapping', () {
    test('the four synced sports, by catalogue name', () {
      expect(stravaSportFor('Running')?.sportType, 'Run');
      expect(stravaSportFor('Walking')?.sportType, 'Walk');
      expect(stravaSportFor('Football')?.sportType, 'Soccer');
      expect(stravaSportFor('Padel')?.sportType, 'Padel');
    });

    test('anything else is not uploaded', () {
      expect(stravaSportFor('Weight training'), isNull);
      expect(stravaSportFor(null), isNull);
    });
  });

  group('TCX', () {
    const start = 1792300000000;

    test('HR only: every point has a time and a heart rate, no position', () {
      final tcx = buildTcx(
        sport: 'Other',
        startMs: start,
        endMs: start + 60000,
        points: mergeTrack(fixes: const [], hr: const [
          (tsMs: start, hr: 120),
          (tsMs: start + 1000, hr: 124),
        ]),
        calories: 12.4,
      );
      expect(tcx, contains('<Activity Sport="Other">'));
      expect(tcx, contains('<TotalTimeSeconds>60</TotalTimeSeconds>'));
      expect(tcx, contains('<Calories>12</Calories>'));
      expect('<Trackpoint>'.allMatches(tcx).length, 2);
      expect(tcx, contains('<HeartRateBpm><Value>124</Value></HeartRateBpm>'));
      expect(tcx, isNot(contains('<Position>')));
    });

    test('a route keeps its fixes and takes the nearest beat within 3 s', () {
      final pts = mergeTrack(fixes: const [
        (tsMs: start, lat: 48.1, lng: 11.5, alt: 520.0),
        (tsMs: start + 10000, lat: 48.2, lng: 11.6, alt: null),
      ], hr: const [
        (tsMs: start + 1000, hr: 140),
      ]);
      expect(pts.first.hr, 140);
      expect(pts.last.hr, isNull, reason: 'no beat within 3 s of it');
      final tcx =
          buildTcx(sport: 'Running', startMs: start, endMs: start + 10000, points: pts);
      expect('<Position>'.allMatches(tcx).length, 2);
      expect(tcx, contains('<AltitudeMeters>520.0</AltitudeMeters>'));
    });

    test('a broken fix with no beat is dropped, never written', () {
      final tcx = buildTcx(
          sport: 'Running',
          startMs: start,
          endMs: start + 1000,
          points: const [(tsMs: start, hr: null, lat: double.nan, lng: 1.0, alt: null)]);
      expect(tcx, isNot(contains('<Trackpoint>')));
    });
  });

  group('API', () {
    test('the login asks for activity:write and the turbohealth redirect', () {
      final u = StravaApi().authorizeUrl('12345');
      expect(u.queryParameters['client_id'], '12345');
      expect(u.queryParameters['redirect_uri'], 'turbohealth://localhost');
      expect(u.queryParameters['scope'], contains('activity:write'));
    });

    test('a duplicate upload resolves to the existing activity', () async {
      final api = StravaApi(
          client: MockClient((_) async => http.Response(
              jsonEncode({
                'id': 1,
                'error': 'w123.tcx duplicate of <a href=\'/activities/987\'>x</a>',
                'activity_id': null,
              }),
              200)));
      expect(await api.uploadStatus('t', 1), 987);
    });

    test('a rejected file throws with Strava\'s reason', () async {
      final api = StravaApi(
          client: MockClient((_) async => http.Response(
              jsonEncode({'id': 1, 'error': 'Time information is missing'}),
              200)));
      expect(() => api.uploadStatus('t', 1), throwsA(isA<StravaException>()));
    });

    test('a refused sport type returns false, so Workout is the fallback',
        () async {
      final api = StravaApi(
          client: MockClient((r) async {
        expect(r.headers['Authorization'], 'Bearer t');
        return http.Response('{"message":"Bad Request"}', 400);
      }));
      expect(await api.setSport('t', 5, 'Padel'), isFalse);
    });
  });

  group('when to upload', () {
    const end = 1792300000;
    test('beats up to the end: upload', () {
      expect(
          stravaReady(
              lastHrMs: (end - 5) * 1000, hasRoute: false, endSec: end, nowSec: end + 60),
          StravaReady.upload);
    });
    test('no beats yet right after finishing: wait for the sync', () {
      expect(stravaReady(lastHrMs: null, hasRoute: false, endSec: end, nowSec: end + 5),
          StravaReady.wait);
    });
    test('beats stop well before the end: still waiting', () {
      expect(
          stravaReady(
              lastHrMs: (end - 900) * 1000, hasRoute: true, endSec: end, nowSec: end + 600),
          StravaReady.wait);
    });
    test('two hours on: send what there is, or nothing at all', () {
      expect(
          stravaReady(lastHrMs: null, hasRoute: true, endSec: end, nowSec: end + 7300),
          StravaReady.upload);
      expect(
          stravaReady(lastHrMs: null, hasRoute: false, endSec: end, nowSec: end + 7300),
          StravaReady.nothing);
    });
  });
}
