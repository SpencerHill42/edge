// Commute rides nobody started (Strap Cockpit, Armin 2026-10-18).
//
// Armin cycles to work and forgets to start a workout. The iPhone's motion
// coprocessor classifies cycling on its own and keeps that log for seven days
// (MotionActivityBridge in AppDelegate.swift), so after the fact we can ask
// "when was cycling?", take the band's heart rate for that span, and save it as
// a Cycling session that goes to Strava as a commute Ride.
//
// Guards, so a car ride or a Wahoo tour does not become a commute:
//   · 5–60 minutes: longer rides are recorded on the Wahoo and reach Strava
//     from there; a commute-flagged copy would be a duplicate.
//   · the band's HR covers at least half the span and averages at least
//     resting HR + 25 (≈ 70 for Armin, whose RHR is ~45; a fixed 85 missed
//     his easy rides home at 74–81): iOS sometimes reads a bumpy car ride as
//     cycling, and sitting in a car does not raise the pulse.
//   · nothing already recorded overlaps it (a manually started ride wins).
//     An earlier, shorter auto-commute piece of the same ride is replaced.
//
// iOS's cycling classification is patchy with the phone in a bag: one 20-minute
// ride arrives as 1, 2, 8 and 4 minutes with gaps of up to 8 (Armin's log,
// 2026-10-21), so pieces up to [kRideGapMs] apart are one ride.
// A ride whose beats have not synced yet is left for the next run, until a
// day has passed.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/activity_store.dart';
import '../data/day_label.dart';
import '../data/db.dart';
import '../models/activity_suggestion.dart';
import '../notify/notification_center.dart';
import '../notify/notification_event.dart';
import '../notify/tap_router.dart' show activitySuggestionRoute;
import '../sync/file_log.dart';

/// One entry of iOS's activity log: when the phone's classification changed,
/// whether it now says cycling, and how sure it is (0 low, 1 medium, 2 high).
typedef MotionChange = ({
  int startMs,
  bool cycling,
  int confidence,
  bool automotive,
});

/// How long iOS said "in a vehicle" (medium or high confidence) inside a span.
/// Armin's evening "rides" of 2026-10-20/21 were the U-Bahn and the car: the
/// vibration reads as cycling pieces, and merged they looked like a ride.
int vehicleMsIn(List<MotionChange> log, int fromMs, int toMs,
    {required int untilMs}) {
  var ms = 0;
  for (var i = 0; i < log.length; i++) {
    final a = log[i];
    if (!a.automotive || a.confidence < 1) continue;
    final end = i + 1 < log.length ? log[i + 1].startMs : untilMs;
    final s = a.startMs < fromMs ? fromMs : a.startMs;
    final e = end > toMs ? toMs : end;
    if (e > s) ms += e - s;
  }
  return ms;
}

/// Cycling spans out of the activity log. A stop at a traffic light reads as a
/// short non-cycling stretch; gaps up to [mergeGapMs] are bridged. Low
/// confidence does not count as cycling.
const kRideGapMs = 10 * 60 * 1000;

List<({int startMs, int endMs})> cyclingSpans(
  List<MotionChange> log, {
  required int untilMs,
  int mergeGapMs = kRideGapMs,
}) {
  final raw = <({int startMs, int endMs})>[];
  for (var i = 0; i < log.length; i++) {
    final a = log[i];
    if (!a.cycling || a.confidence < 1) continue;
    final end = i + 1 < log.length ? log[i + 1].startMs : untilMs;
    if (end > a.startMs) raw.add((startMs: a.startMs, endMs: end));
  }
  final out = <({int startMs, int endMs})>[];
  for (final s in raw) {
    if (out.isNotEmpty && s.startMs - out.last.endMs <= mergeGapMs) {
      out[out.length - 1] = (startMs: out.last.startMs, endMs: s.endMs);
    } else {
      out.add(s);
    }
  }
  return out;
}

/// What to do with one cycling span.
enum CommuteVerdict { save, wait, skip }

CommuteVerdict commuteVerdict({
  required int durationSec,
  required int hrSamples,
  required double? meanHr,
  required bool overlapsSession,
  required int ageSec,
  double? restingHr,
  int vehicleSec = 0,
}) {
  if (durationSec < 5 * 60 || durationSec > 60 * 60) return CommuteVerdict.skip;
  // Two minutes of "in a vehicle" inside it: a train or a car, not a bike.
  if (vehicleSec >= 120) return CommuteVerdict.skip;
  if (overlapsSession) return CommuteVerdict.skip;
  final covered = hrSamples >= durationSec / 2;
  if (!covered) {
    // The band syncs after the ride; give it a day before giving up.
    return ageSec < 24 * 3600 ? CommuteVerdict.wait : CommuteVerdict.skip;
  }
  final floor = (restingHr ?? 60) + 25;
  return (meanHr ?? 0) >= floor ? CommuteVerdict.save : CommuteVerdict.skip;
}

class CommuteRides {
  static final instance = CommuteRides();
  static const _channel = MethodChannel('openstrap/motion_activity');
  // v2: the decisions made with the 3-minute merge and the fixed 85 bpm are
  // not carried over, so the last days are judged again under the new rules.
  static const _kDone = 'commute.decided.v3';
  bool _running = false;

  /// Look at the last two days of the activity log and save the commute rides
  /// in it. Run on launch, foreground and after every derive. Never throws.
  Future<void> run({DateTime? now}) async {
    if (_running) return;
    _running = true;
    try {
      final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
      final fromMs = nowMs - 2 * 24 * 3600 * 1000;
      final raw = await _channel.invokeListMethod<Map>('activities',
              {'fromMs': fromMs, 'toMs': nowMs}) ??
          const [];
      final log = <MotionChange>[
        for (final m in raw)
          (
            startMs: (m['startMs'] as num).toInt(),
            cycling: m['cycling'] == true,
            confidence: (m['confidence'] as num?)?.toInt() ?? 0,
            automotive: m['automotive'] == true,
          ),
      ];
      final spans = cyclingSpans(log, untilMs: nowMs);
      // Diagnostics in openstrap_sync.log (Files app): what iOS reported and
      // what became of each span. Commute detection is a heuristic on a
      // classifier we do not control; the log is how it gets tuned.
      if (spans.isNotEmpty) {
        await FileLog.write('[commute] ${log.length} activity changes, '
            '${log.where((a) => a.cycling).length} cycling, '
            '${spans.length} span(s): ${[
              for (final s in spans)
                '${DateTime.fromMillisecondsSinceEpoch(s.startMs)}'
                    '+${(s.endMs - s.startMs) ~/ 60000}min'
            ].join(', ')}');
      }
      final prefs = await SharedPreferences.getInstance();
      // One-time: the two auto-saved "rides" that were the U-Bahn (20.10.)
      // and the car (21.10.), deleted by Armin on Strava, go from the app.
      if (prefs.getBool('commute.cleanup.v1') != true) {
        for (final bad in const ['commute_1792511292', 'commute_1792596770']) {
          if ((await LocalDb.session(bad))?['source'] == kCommuteSource) {
            await LocalDb.deleteSession(bad);
            await FileLog.write('[commute] removed $bad (U-Bahn/car)');
          }
        }
        await prefs.setBool('commute.cleanup.v1', true);
      }
      final decided = (jsonDecode(prefs.getString(_kDone) ?? '[]') as List)
          .cast<String>()
          .toSet();
      // A span still growing (the ride is under way) is not judged yet.
      for (final s in spans) {
        if (nowMs - s.endMs < 2 * 60 * 1000) continue;
        final id = 'commute_${s.startMs ~/ 1000}';
        if (decided.contains(id)) continue;
        // Proposals live in the review now; a ride already proposed there is
        // not proposed twice.
        final start = s.startMs ~/ 1000, end = s.endMs ~/ 1000;
        final hr = await LocalDb.hrSamplesInRange(start, end);
        final bpm = [for (final r in hr) (r['hr'] as num).toDouble()];
        final near = await LocalDb.sessionsInRange(start - 4 * 3600, end);
        bool hits(Map<String, dynamic> x) {
          final xs = (x['start_ts'] as num?)?.toInt() ?? 0;
          final xe = (x['end_ts'] as num?)?.toInt() ?? xs;
          return x['id'] != id && xs < end && xe > start;
        }
        // An auto-commute piece of this same ride (saved before the pieces
        // merged) does not block it: it is replaced below.
        final pieces = [
          for (final x in near)
            if (hits(x) && x['source'] == kCommuteSource) x['id'] as String,
        ];
        final overlaps =
            near.any((x) => hits(x) && x['source'] != kCommuteSource);
        final rhr = await LocalDb.trailingSeriesValues('rhr', 14);
        final verdict = commuteVerdict(
          durationSec: end - start,
          hrSamples: bpm.length,
          meanHr: bpm.isEmpty ? null : bpm.reduce((a, b) => a + b) / bpm.length,
          overlapsSession: overlaps,
          ageSec: nowMs ~/ 1000 - end,
          restingHr:
              rhr.isEmpty ? null : rhr.reduce((a, b) => a + b) / rhr.length,
          vehicleSec: vehicleMsIn(log, s.startMs, s.endMs, untilMs: nowMs) ~/ 1000,
        );
        await FileLog.write('[commute] ${DateTime.fromMillisecondsSinceEpoch(s.startMs)} '
            '${(end - start) ~/ 60} min, ${bpm.length} beats, mean '
            '${bpm.isEmpty ? '-' : (bpm.reduce((a, b) => a + b) / bpm.length).round()} '
            'bpm, vehicle ${vehicleMsIn(log, s.startMs, s.endMs, untilMs: nowMs) ~/ 60000} min, '
            'overlap $overlaps -> ${verdict.name}');
        if (verdict == CommuteVerdict.wait) continue;
        decided.add(id);
        if (verdict == CommuteVerdict.skip) {
          // A ride saved under the earlier, looser rules that is not one any
          // more (Armin deleted two on Strava: U-Bahn and car) goes from the
          // app too.
          for (final old in [id, ...pieces]) {
            if ((await LocalDb.session(old))?['source'] == kCommuteSource) {
              await LocalDb.deleteSession(old);
              await FileLog.write('[commute] removed $old (not a ride)');
            }
          }
          continue;
        }
        for (final old in pieces) {
          await LocalDb.deleteSession(old);
          await FileLog.write('[commute] replaced the shorter piece $old');
        }
        // Weg B (Armin, 2026-10-21): iOS cannot tell his U-Bahn or car from a
        // bike, so a detected ride is only a PROPOSAL. It joins the "Hast du
        // trainiert?" review as a Radfahrt; confirming it saves the session
        // (id 'suggestion:commute:<start>') and sends it to Strava as a
        // commute, discarding it leaves nothing behind.
        final store = ActivityStore(await LocalDb.instance);
        final created = await store.reconcile(ActivityKind.workout, [
          {
            'id': 'commute:$start',
            'start_ts': start,
            'end_ts': end,
            'sport': 'Cycling',
            'commute': true,
            'max_hr': bpm.reduce((a, b) => a > b ? a : b).round(),
          },
        ]);
        for (final sug in created) {
          if (!await store.mayNotifyNew(sug)) continue;
          String hm(int t) {
            final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
            return '${d.hour.toString().padLeft(2, '0')}:'
                '${d.minute.toString().padLeft(2, '0')}';
          }
          await NotificationCenter.instance.emit(
              NotificationEvent(
                dedupeKey: '${sug.startTs}:activity:${sug.id}',
                category: NotifCategory.reminders,
                priority: NotifPriority.normal,
                title: 'Radfahrt erkannt',
                body: '${hm(sug.startTs)}–${hm(sug.endTs)}, '
                    '${sug.durationMin} Min. Tippe, um sie zu bestätigen: '
                    'dann geht sie zu Strava.',
                date: dayLabelOf(
                    DateTime.fromMillisecondsSinceEpoch(sug.startTs * 1000)),
                route: activitySuggestionRoute(sug.id, sug.kind.name),
              ),
              allowPermissionPrompt: false);
        }
        await FileLog.write('[commute] proposed commute:$start for review');
      }
      // Bounded: a week of decisions is all the activity log can ever offer.
      final keep = decided.where((d) {
        final t = int.tryParse(d.split('_').last) ?? 0;
        return nowMs ~/ 1000 - t < 8 * 24 * 3600;
      }).toList();
      await prefs.setString(_kDone, jsonEncode(keep));
    } catch (e, st) {
      debugPrint('[commute] $e');
      await FileLog.write('[commute] failed: $e ${st.toString().split('\n').take(3).join(' | ')}');
    } finally {
      _running = false;
    }
  }
}

/// `sessions.source` of a ride saved from the activity log. Strava marks
/// these as commutes.
const kCommuteSource = 'auto_commute';
