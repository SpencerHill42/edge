// WHEN workouts go to Strava, and what the app remembers about each upload.
//
// A finished session of a synced sport is queued; the queue drains right away
// and again on every foreground, so a workout finished offline goes up the
// next time the app opens. Per session the state lives in shared preferences
// (a private app with a handful of workouts a week does not need a table):
// queued → uploading → done (with the Strava activity id) or failed (with
// Strava's reason, retried on the next drain and by the summary's button).
//
// The session id is the upload's `external_id`, so a retry after a crash or a
// lost answer cannot create a second activity.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import 'commute.dart' show kCommuteSource;
import 'strava.dart';

enum StravaState { queued, waiting, uploading, done, failed }

/// Whether a session's data is complete enough to upload.
///
/// The band hands its 1 Hz heart rate over in the sync AFTER the workout, so
/// at the moment of "finish" the session usually has no beats yet (seen on
/// Armin's first walk). Upload once the beats reach the end of the session;
/// wait otherwise; after [patience] stop waiting and send what there is, or
/// nothing when there is neither a beat nor a route.
enum StravaReady { upload, wait, nothing }

StravaReady stravaReady({
  required int? lastHrMs,
  required bool hasRoute,
  required int endSec,
  required int nowSec,
  int patience = 2 * 3600,
}) {
  if (lastHrMs != null && lastHrMs >= (endSec - 60) * 1000) {
    return StravaReady.upload;
  }
  if (nowSec - endSec < patience) return StravaReady.wait;
  return (lastHrMs != null || hasRoute) ? StravaReady.upload : StravaReady.nothing;
}

class StravaUpload {
  final StravaState state;
  final int? activityId;
  final String? error;
  const StravaUpload(this.state, {this.activityId, this.error});

  Map<String, Object?> toJson() =>
      {'state': state.name, 'activity_id': activityId, 'error': error};

  static StravaUpload? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = StravaState.values.where((v) => v.name == j['state']).firstOrNull;
    if (s == null) return null;
    return StravaUpload(s,
        activityId: (j['activity_id'] as num?)?.toInt(),
        error: j['error'] as String?);
  }
}

class StravaSync {
  StravaSync({StravaVault? vault, StravaApi? api})
      : vault = vault ?? StravaVault(),
        api = api ?? StravaApi();

  static final instance = StravaSync();

  final StravaVault vault;
  final StravaApi api;

  /// Bumped on every state change, for the summary and the Strava screen.
  final revision = ValueNotifier<int>(0);

  static const _kStates = 'strava.uploads';
  bool _draining = false;

  // ── state ──

  Future<Map<String, StravaUpload>> _all() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kStates);
      if (raw == null) return {};
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries) e.key: ?StravaUpload.fromJson(e.value),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _put(String id, StravaUpload u) async {
    final all = await _all();
    all[id] = u;
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kStates, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
    revision.value++;
  }

  Future<StravaUpload?> stateOf(String sessionId) async =>
      (await _all())[sessionId];

  Future<bool> get connected async => await vault.tokens() != null;

  // ── the queue ──

  /// Queue a finished session when it is a synced sport and Strava is
  /// connected, then drain. Never throws.
  Future<void> onSessionFinished(String sessionId, String? type) async {
    try {
      if (stravaSportFor(type) == null || !await connected) return;
      final have = await stateOf(sessionId);
      if (have?.state == StravaState.done) return;
      await _put(sessionId, const StravaUpload(StravaState.queued));
      unawaited(drain());
    } catch (e) {
      debugPrint('[strava] queue: $e');
    }
  }

  /// Retry one session now (the summary's button).
  Future<void> retry(String sessionId) async {
    await _put(sessionId, const StravaUpload(StravaState.queued));
    await drain();
  }

  /// Upload everything queued or waiting for band data, and with
  /// [includeFailed] (foreground, the retry button) the failed ones too — a
  /// derive tick must not hammer Strava with a request it already refused.
  /// One drain at a time; never throws.
  Future<void> drain({bool includeFailed = true}) async {
    if (_draining) return;
    _draining = true;
    try {
      final all = await _all();
      if (!all.values.any((u) => u.state != StravaState.done)) return;
      if (!await connected) return;
      for (final e in all.entries) {
        if (e.value.state == StravaState.done) continue;
        if (e.value.state == StravaState.failed && !includeFailed) continue;
        await _uploadOne(e.key);
      }
    } catch (e) {
      debugPrint('[strava] drain: $e');
    } finally {
      _draining = false;
    }
  }

  Future<String> _token() async {
    final creds = await vault.credentials();
    var t = await vault.tokens();
    if (creds == null || t == null) {
      throw const StravaException('nicht verbunden');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (t.expiresAt - now < 300) {
      t = await api.refresh(creds.id, creds.secret, t);
      await vault.saveTokens(t);
    }
    return t.access;
  }

  Future<void> _uploadOne(String id) async {
    try {
      final s = await LocalDb.session(id);
      final sport = stravaSportFor(s?['type'] as String?);
      final start = (s?['start_ts'] as num?)?.toInt();
      final end = (s?['end_ts'] as num?)?.toInt();
      if (s == null || sport == null || start == null || end == null) {
        await _put(id, const StravaUpload(StravaState.failed,
            error: 'Training nicht gefunden'));
        return;
      }
      final hrRows = await LocalDb.hrSamplesInRange(start, end);
      final hr = [
        for (final r in hrRows)
          (tsMs: (r['rec_ts'] as num).toInt() * 1000, hr: (r['hr'] as num).toInt()),
      ];
      final fixes = [
        for (final r in await LocalDb.routePoints(id))
          (
            tsMs: (r['ts_ms'] as num).toInt(),
            lat: (r['lat'] as num).toDouble(),
            lng: (r['lng'] as num).toDouble(),
            alt: (r['alt'] as num?)?.toDouble(),
          ),
      ];
      switch (stravaReady(
          lastHrMs: hr.isEmpty ? null : hr.last.tsMs,
          hasRoute: fixes.length >= 2,
          endSec: end,
          nowSec: DateTime.now().millisecondsSinceEpoch ~/ 1000)) {
        case StravaReady.wait:
          await _put(id, const StravaUpload(StravaState.waiting));
          return;
        case StravaReady.nothing:
          // Nothing to draw a graph from: an upload would be an empty file.
          await _put(id, const StravaUpload(StravaState.failed,
              error: 'Keine Herzfrequenz und keine Route aufgezeichnet'));
          return;
        case StravaReady.upload:
          await _put(id, const StravaUpload(StravaState.uploading));
      }
      final tcx = buildTcx(
        sport: sport.sport,
        startMs: start * 1000,
        endMs: end * 1000,
        points: mergeTrack(fixes: fixes.length < 2 ? const [] : fixes, hr: hr),
        calories: (s['calories'] as num?)?.toDouble(),
      );
      final token = await _token();
      // An auto-saved ride (before review existed) or a confirmed proposal.
      final commute = s['source'] == kCommuteSource ||
          id.startsWith('suggestion:commute:');
      final name = commute ? 'Pendelfahrt' : sport.name;
      final uploadId = await api.upload(token,
          tcx: tcx, externalId: id, name: name, commute: commute);
      int? activity;
      // Strava processes in a few seconds; poll at ≥ 1 s, give up after ~1 min
      // and leave it failed-with-reason for the next drain.
      for (var i = 0; i < 30 && activity == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        activity = await api.uploadStatus(token, uploadId);
      }
      if (activity == null) {
        await _put(id, const StravaUpload(StravaState.failed,
            error: 'Strava verarbeitet noch, später erneut'));
        return;
      }
      // Padel is in Strava's app list but may be missing from the API enum:
      // fall back to Workout with the sport in the name.
      if (!await api.setSport(token, activity, sport.sportType,
          name: name, commute: commute ? true : null)) {
        await api.setSport(token, activity, 'Workout', name: name);
      }
      await _put(id, StravaUpload(StravaState.done, activityId: activity));
    } catch (e) {
      debugPrint('[strava] upload $id: $e');
      await _put(id, StravaUpload(StravaState.failed,
          error: e is StravaException ? e.message : '$e'));
    }
  }

  // ── connect / disconnect ──

  /// The OAuth round trip after the credentials are saved. Returns the
  /// athlete's name, or null when the login sheet was cancelled.
  Future<String?> connect() async {
    final creds = await vault.credentials();
    if (creds == null) throw const StravaException('Client-ID und Secret fehlen');
    final code = await stravaLogin(api.authorizeUrl(creds.id));
    if (code == null) return null;
    final t = await api.exchange(creds.id, creds.secret, code);
    await vault.saveTokens(t);
    revision.value++;
    unawaited(drain());
    return t.athlete ?? '';
  }

  Future<void> disconnect() async {
    final t = await vault.tokens();
    if (t != null) {
      try {
        await api.deauthorize(t.access);
      } catch (_) {}
    }
    await vault.clearTokens();
    revision.value++;
  }
}
