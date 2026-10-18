// Strava sync (Strap Cockpit, Armin 2026-10-18, docs/TODO.md item 6).
//
// Finished workouts of four sports go to Armin's Strava account as a TCX file
// upload, so the heart-rate graph (and, with GPS, the map) survives. Writes
// only: nothing read from Strava ever reaches the coach or any analytics
// (Strava API agreement: no Strava data in AI features).
//
// Credentials never ship in the build — the IPA is built on a public repo.
// The client ID and secret are pasted once on the Strava screen and kept in
// the keychain with the OAuth tokens, the same pattern as the coach's BYOK key.
//
// Pure pieces (sport mapping, TCX, the HTTP client with an injectable
// `http.Client`) are here and tested in test/strava_test.dart; the queue that
// decides WHEN to upload is `strava_sync.dart`.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Strava's names for the four sports Armin syncs, keyed by the session's
/// `type` (the catalogue name, lower-cased). Anything else is not uploaded.
///
/// `sport` is the TCX `Activity Sport` (Running / Biking / Other are the only
/// values the schema allows); `sportType` is set afterwards with
/// `PUT /activities/{id}`, because an upload cannot carry it.
const kStravaSports = <String, ({String sport, String sportType, String name})>{
  'running': (sport: 'Running', sportType: 'Run', name: 'Lauf'),
  'walking': (sport: 'Other', sportType: 'Walk', name: 'Spaziergang'),
  'football': (sport: 'Other', sportType: 'Soccer', name: 'Fußball'),
  'padel': (sport: 'Other', sportType: 'Padel', name: 'Padel'),
};

/// The Strava mapping for a session `type`, or null when it is not synced.
({String sport, String sportType, String name})? stravaSportFor(String? type) =>
    type == null ? null : kStravaSports[type.trim().toLowerCase().replaceAll(' ', '_')];

/// One trackpoint: a time, a heart rate, and a position when the workout
/// recorded a route.
typedef StravaPoint = ({int tsMs, int? hr, double? lat, double? lng, double? alt});

/// A TCX document (Garmin TrainingCenterDatabase v2) for one workout.
///
/// Every trackpoint carries a time; HR and position only when known — Strava
/// documents both as optional, so a football session is HR on a timeline and
/// a run is HR on its route. [points] must be time-ordered.
String buildTcx({
  required String sport,
  required int startMs,
  required int endMs,
  required List<StravaPoint> points,
  double? calories,
}) {
  String iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<TrainingCenterDatabase '
        'xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">')
    ..writeln('<Activities><Activity Sport="$sport">')
    ..writeln('<Id>${iso(startMs)}</Id>')
    ..writeln('<Lap StartTime="${iso(startMs)}">')
    ..writeln('<TotalTimeSeconds>${((endMs - startMs) / 1000).round()}'
        '</TotalTimeSeconds>')
    ..writeln('<DistanceMeters>0</DistanceMeters>')
    ..writeln('<Calories>${(calories ?? 0).round()}</Calories>')
    ..writeln('<Intensity>Active</Intensity>')
    ..writeln('<TriggerMethod>Manual</TriggerMethod>')
    ..writeln('<Track>');
  for (final p in points) {
    final hasPos = p.lat != null &&
        p.lng != null &&
        !p.lat!.isNaN &&
        !p.lng!.isNaN &&
        p.lat!.abs() <= 90 &&
        p.lng!.abs() <= 180;
    if (!hasPos && p.hr == null) continue;
    buf.write('<Trackpoint><Time>${iso(p.tsMs)}</Time>');
    if (hasPos) {
      buf.write('<Position><LatitudeDegrees>${p.lat}</LatitudeDegrees>'
          '<LongitudeDegrees>${p.lng}</LongitudeDegrees></Position>');
      if (p.alt != null) buf.write('<AltitudeMeters>${p.alt}</AltitudeMeters>');
    }
    if (p.hr != null) {
      buf.write('<HeartRateBpm><Value>${p.hr}</Value></HeartRateBpm>');
    }
    buf.writeln('</Trackpoint>');
  }
  buf.writeln('</Track></Lap></Activity></Activities></TrainingCenterDatabase>');
  return buf.toString();
}

/// Route fixes and HR samples merged into one time-ordered list: every fix
/// gets the nearest beat within 3 s; without a route, every HR sample is a
/// point on its own.
List<StravaPoint> mergeTrack({
  required List<({int tsMs, double lat, double lng, double? alt})> fixes,
  required List<({int tsMs, int hr})> hr,
}) {
  if (fixes.isEmpty) {
    return [
      for (final h in hr) (tsMs: h.tsMs, hr: h.hr, lat: null, lng: null, alt: null),
    ];
  }
  var i = 0;
  int? near(int ts) {
    if (hr.isEmpty) return null;
    while (i + 1 < hr.length &&
        (hr[i + 1].tsMs - ts).abs() <= (hr[i].tsMs - ts).abs()) {
      i++;
    }
    return (hr[i].tsMs - ts).abs() <= 3000 ? hr[i].hr : null;
  }

  return [
    for (final f in fixes)
      (tsMs: f.tsMs, hr: near(f.tsMs), lat: f.lat, lng: f.lng, alt: f.alt),
  ];
}

// ── credentials and tokens ─────────────────────────────────────────────────

class StravaTokens {
  final String access, refresh;
  final int expiresAt; // epoch seconds
  final String? athlete;
  const StravaTokens(this.access, this.refresh, this.expiresAt, {this.athlete});
}

/// Keychain storage for the API app's credentials and the OAuth tokens.
class StravaVault {
  StravaVault({FlutterSecureStorage? storage})
      : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const _kId = 'strava.client_id',
      _kSecret = 'strava.client_secret',
      _kTokens = 'strava.tokens';

  Future<({String id, String secret})?> credentials() async {
    final id = await _s.read(key: _kId);
    final secret = await _s.read(key: _kSecret);
    if (id == null || id.isEmpty || secret == null || secret.isEmpty) return null;
    return (id: id, secret: secret);
  }

  Future<void> saveCredentials(String id, String secret) async {
    await _s.write(key: _kId, value: id.trim());
    await _s.write(key: _kSecret, value: secret.trim());
  }

  Future<StravaTokens?> tokens() async {
    final raw = await _s.read(key: _kTokens);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return StravaTokens(m['access'] as String, m['refresh'] as String,
          (m['expires_at'] as num).toInt(),
          athlete: m['athlete'] as String?);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTokens(StravaTokens t) => _s.write(
      key: _kTokens,
      value: jsonEncode({
        'access': t.access,
        'refresh': t.refresh,
        'expires_at': t.expiresAt,
        'athlete': t.athlete,
      }));

  Future<void> clearTokens() => _s.delete(key: _kTokens);
}

// ── the API ────────────────────────────────────────────────────────────────

class StravaException implements Exception {
  final String message;
  final int? status;
  const StravaException(this.message, {this.status});
  @override
  String toString() => 'Strava: $message${status == null ? '' : ' ($status)'}';
}

/// The few calls the sync needs. [base] moves to api-v3.strava.com on
/// 2027-01-04; tokens already go in the Authorization header (required from
/// 2027-06-01).
class StravaApi {
  StravaApi({http.Client? client, this.base = 'https://www.strava.com'})
      : _http = client ?? http.Client();
  final http.Client _http;
  final String base;

  static const redirectUri = 'turbohealth://localhost';
  static const scope = 'activity:write,activity:read';

  Uri authorizeUrl(String clientId) =>
      Uri.parse('$base/oauth/mobile/authorize').replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': scope,
      });

  Future<StravaTokens> _token(Map<String, String> body) async {
    final r = await _http.post(Uri.parse('$base/oauth/token'), body: body);
    if (r.statusCode != 200) {
      throw StravaException('token: ${r.body}', status: r.statusCode);
    }
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final a = m['athlete'] as Map<String, dynamic>?;
    return StravaTokens(m['access_token'] as String,
        m['refresh_token'] as String, (m['expires_at'] as num).toInt(),
        athlete: a == null
            ? null
            : [a['firstname'], a['lastname']].whereType<String>().join(' '));
  }

  Future<StravaTokens> exchange(String id, String secret, String code) =>
      _token({
        'client_id': id,
        'client_secret': secret,
        'code': code,
        'grant_type': 'authorization_code',
      });

  Future<StravaTokens> refresh(String id, String secret, StravaTokens t) async {
    final n = await _token({
      'client_id': id,
      'client_secret': secret,
      'refresh_token': t.refresh,
      'grant_type': 'refresh_token',
    });
    // A refresh answer carries no athlete; keep the name we had.
    return StravaTokens(n.access, n.refresh, n.expiresAt, athlete: t.athlete);
  }

  Map<String, String> _auth(String token) => {'Authorization': 'Bearer $token'};

  /// Start an upload; returns the upload id. A duplicate `external_id` comes
  /// back as an error naming the existing activity, which the caller treats as
  /// done rather than as a failure.
  Future<int> upload(String token,
      {required String tcx,
      required String externalId,
      required String name}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$base/api/v3/uploads'))
      ..headers.addAll(_auth(token))
      ..fields['data_type'] = 'tcx'
      ..fields['external_id'] = externalId
      ..fields['name'] = name
      ..files.add(http.MultipartFile.fromBytes('file', utf8.encode(tcx),
          filename: '$externalId.tcx'));
    final r = await http.Response.fromStream(await _http.send(req));
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw StravaException('upload: ${r.body}', status: r.statusCode);
    }
    return ((jsonDecode(r.body) as Map<String, dynamic>)['id'] as num).toInt();
  }

  /// One status read: the activity id once processed, null while processing.
  /// Throws with Strava's own error text when the file was rejected.
  Future<int?> uploadStatus(String token, int uploadId) async {
    final r = await _http.get(Uri.parse('$base/api/v3/uploads/$uploadId'),
        headers: _auth(token));
    if (r.statusCode != 200) {
      throw StravaException('status: ${r.body}', status: r.statusCode);
    }
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final err = m['error'] as String?;
    if (err != null && err.isNotEmpty) {
      final dup = RegExp(r'duplicate of .*?/activities/(\d+)').firstMatch(err) ??
          RegExp(r'duplicate of activity (\d+)').firstMatch(err);
      if (dup != null) return int.parse(dup.group(1)!);
      throw StravaException(err);
    }
    return (m['activity_id'] as num?)?.toInt();
  }

  /// Set the sport (and name). Returns false when Strava refuses the sport —
  /// the caller then falls back to `Workout`.
  Future<bool> setSport(String token, int activityId, String sportType,
      {String? name}) async {
    final r = await _http.put(Uri.parse('$base/api/v3/activities/$activityId'),
        headers: {..._auth(token), 'Content-Type': 'application/json'},
        body: jsonEncode({'sport_type': sportType, 'name': ?name}));
    if (r.statusCode == 200) return true;
    if (r.statusCode == 400 || r.statusCode == 422) return false;
    throw StravaException('update: ${r.body}', status: r.statusCode);
  }

  Future<void> deauthorize(String token) => _http.post(
      Uri.parse('$base/oauth/deauthorize'),
      headers: _auth(token));
}

// ── the login sheet ────────────────────────────────────────────────────────

/// ASWebAuthenticationSession through `openstrap/strava_auth` (AppDelegate):
/// Apple's own login sheet, no URL scheme registration and no web-auth
/// dependency. Returns the authorization code, or null when cancelled.
Future<String?> stravaLogin(Uri url) async {
  try {
    final cb = await const MethodChannel('openstrap/strava_auth')
        .invokeMethod<String>('authorize', {
      'url': url.toString(),
      'scheme': 'turbohealth',
    });
    if (cb == null) return null;
    final u = Uri.parse(cb);
    final err = u.queryParameters['error'];
    if (err != null) throw StravaException(err);
    // Strava echoes the granted scope; without activity:write nothing can be
    // uploaded, so a login that unticked it is not a connection.
    final granted = u.queryParameters['scope'] ?? '';
    if (!granted.contains('activity:write')) {
      throw const StravaException('activity:write not granted');
    }
    return u.queryParameters['code'];
  } on PlatformException catch (e) {
    if (e.code == 'cancelled') return null;
    debugPrint('[strava] login: $e');
    rethrow;
  }
}
