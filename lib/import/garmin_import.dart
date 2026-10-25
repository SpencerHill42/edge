// garmin_import.dart — import a Garmin Connect data export (GDPR "Export
// your data", the DI_CONNECT folder).
//
// Like the WHOOP import this writes derived-snapshot days, one per date, and
// never replaces a day the band measured. Unlike it, the quantities taken are
// MEASUREMENTS, not a vendor's scores: resting HR, overnight HRV (RMSSD),
// breathing rate, sleep and its stages, steps, VO2max. Those days are stamped
// `source: 'garmin_export'` and, by Armin's decision (2026-10-22, "einfließen
// lassen, damit die App sofort eingelernt ist"), they DO feed the personal
// baselines; LocalDb.importedDates leaves them out of the mask. Garmin's own
// scores (sleep score, body battery, training readiness, fitness age) are
// not imported, so nothing in a baseline is somebody else's algorithm.
//
// Files read, by name (anything else in the export is ignored):
//   *_sleepData.json            → sleep window, stages, breathing rate
//   *_healthStatusData.json     → overnight HRV
//   UDSFile_*.json              → steps, that day's resting HR
//   MetricsMaxMetData_*.json    → VO2max
//   *_summarizedActivities.json → sessions
//   turbo_garmin_derived.json   → OUR numbers for those days (see below)
// A ZIP of the export (or of those files) works too.
//
// OUR NUMBERS (Armin, 2026-10-25). `test/garmin_history_replay_test.dart`
// runs the export's monitoring FIT files (1-min HR) through the real Garmin
// path and our engine. Compared with Garmin's own metrics over two years,
// resting HR (r 0.84) and strain (7-day sum vs acute load, r 0.70) held up;
// sleep from 1-min HR alone and the HR-only readiness did not. So that file
// carries only [_derivedKeys], and a day takes them over Garmin's resting HR:
// strain and its baselines learn two years of training, sleep and HRV stay
// Garmin's measurements.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../compute/derivation_engine.dart' show kAlgoVersion, DerivationEngine;
import '../compute/profile.dart';
import '../compute/substrate.dart' show localDateLabel;
import '../data/db.dart';

class GarminImportResult {
  final int days;
  final int workouts;

  /// Days the band already measured; those are never overwritten.
  final int skippedExistingDays;
  const GarminImportResult(this.days, this.workouts, this.skippedExistingDays);
}

enum _GarminFile { sleep, healthStatus, daily, maxMet, activities, derived }

/// What `turbo_garmin_derived.json` may set on a day: our resting HR and
/// strain with the series strain's own baselines read.
const _derivedKeys = {
  'rhr', 'rhr_nocturnal', 'sleeping_hr_nadir', 'dip_pct', 'waking_hr',
  'strain', 'trimp', 'trimp_net', 'quiet_hrr', 'max_hr_used', 'worn_min',
};

_GarminFile? _kindOf(String name) {
  final base = p.basename(name);
  if (base.startsWith('._') || name.startsWith('__MACOSX/')) return null;
  if (base.endsWith('_sleepData.json')) return _GarminFile.sleep;
  if (base.endsWith('_healthStatusData.json')) return _GarminFile.healthStatus;
  if (base.startsWith('UDSFile_') && base.endsWith('.json')) {
    return _GarminFile.daily;
  }
  if (base.startsWith('MetricsMaxMetData_') && base.endsWith('.json')) {
    return _GarminFile.maxMet;
  }
  if (base.endsWith('_summarizedActivities.json')) {
    return _GarminFile.activities;
  }
  if (base == 'turbo_garmin_derived.json') return _GarminFile.derived;
  return null;
}

/// Garmin's activity types → this app's session `type` (the names Strava and
/// Health export map). Unlisted types keep Garmin's slug; [_skipTypes] are not
/// workouts.
const _typeMap = {
  'running': 'running',
  'treadmill_running': 'running',
  'trail_running': 'running',
  'cycling': 'cycling',
  'road_biking': 'cycling',
  'mountain_biking': 'cycling',
  'indoor_cycling': 'cycling',
  'walking': 'walking',
  'paddelball': 'padel',
  'padel': 'padel',
  'platform_tennis': 'tennis',
  'soccer': 'football',
  'lap_swimming': 'swimming',
  'open_water_swimming': 'swimming',
  'hiking': 'hiking',
  'strength_training': 'strength',
  'resort_snowboarding': 'snowboarding',
  'stand_up_paddleboarding_v2': 'paddleboarding',
};
const _skipTypes = {'motorcycling_v2', 'meditation'};

class GarminImporter {
  /// True when [path] is a Garmin export file, or a ZIP holding one.
  static Future<bool> isGarminExport(String path) async {
    if (_kindOf(path) != null) return true;
    if (!path.toLowerCase().endsWith('.zip')) return false;
    final input = InputFileStream(path);
    try {
      return ZipDecoder()
          .decodeStream(input)
          .files
          .any((f) => f.isFile && _kindOf(f.name) != null);
    } catch (_) {
      return false;
    } finally {
      await input.close();
    }
  }

  static Future<GarminImportResult> importFiles(
    List<String> paths, {
    DerivationEngine? engine,
    Profile? profile,
  }) async {
    final docs = <(_GarminFile, Object?)>[];
    for (final path in paths) {
      final kind = _kindOf(path);
      if (kind != null) {
        docs.add((kind, jsonDecode(await File(path).readAsString())));
        continue;
      }
      final input = InputFileStream(path);
      try {
        for (final f in ZipDecoder().decodeStream(input).files) {
          final k = f.isFile ? _kindOf(f.name) : null;
          if (k == null) continue;
          docs.add((k, jsonDecode(utf8.decode(f.readBytes()!))));
        }
      } finally {
        await input.close();
      }
    }
    final res = await _importDocs(docs);
    if (engine != null && profile != null && res.days > 0) {
      await engine.finalizeImport(profile);
    }
    return res;
  }

  static Future<GarminImportResult> _importDocs(
    List<(_GarminFile, Object?)> docs,
  ) async {
    final days = <String, Map<String, num?>>{};
    Map<String, num?> day(String d) => days.putIfAbsent(d, () => {});
    final activities = <Map<String, dynamic>>[];
    final derived = <String, Map<String, double>>{};

    for (final (kind, json) in docs) {
      if (kind == _GarminFile.derived) {
        // {"2025-03-04": {"strain": 9.1, ...}, ...}
        if (json is! Map) continue;
        for (final MapEntry(:key, :value) in json.entries) {
          if (key is! String || value is! Map) continue;
          final keep = <String, double>{
            for (final MapEntry(key: k, value: v) in value.entries)
              if (_derivedKeys.contains(k) && v is num && v.isFinite)
                k as String: v.toDouble(),
          };
          if (keep.isEmpty) continue;
          derived[key] = keep;
          day(key); // a day with only our numbers is still a day
        }
        continue;
      }
      for (final r in _records(json, kind)) {
        switch (kind) {
          case _GarminFile.sleep:
            final on = _gmtSec(r['sleepStartTimestampGMT']);
            final off = _gmtSec(r['sleepEndTimestampGMT']);
            final deep = r['deepSleepSeconds'] as num?;
            final light = r['lightSleepSeconds'] as num?;
            final rem = r['remSleepSeconds'] as num?;
            if (on == null || off == null || off <= on) continue;
            final tst = (deep ?? 0) + (light ?? 0) + (rem ?? 0);
            if (tst <= 0) continue;
            day(localDateLabel(off)).addAll({
              'onset': on,
              'wake': off,
              'tst': tst,
              'deep': deep,
              'light': light,
              'rem': rem,
              'awake': r['awakeSleepSeconds'] as num?,
              'resp': r['averageRespiration'] as num?,
            });
          case _GarminFile.healthStatus:
            final d = r['calendarDate'] as String?;
            if (d == null) continue;
            for (final m in (r['metrics'] as List? ?? const [])) {
              if (m is Map && m['type'] == 'HRV' && m['value'] is num) {
                day(d)['rmssd'] = m['value'] as num;
              }
            }
          case _GarminFile.daily:
            final d = r['calendarDate'] as String?;
            if (d == null) continue;
            // `restingHeartRate` is Garmin's 7-day average; the day's own
            // reading is `currentDayRestingHeartRate`.
            final rhr = r['currentDayRestingHeartRate'] as num?;
            final steps = r['totalSteps'] as num?;
            if (rhr != null && rhr > 0) day(d)['rhr'] = rhr;
            if (steps != null && steps > 0) day(d)['steps'] = steps;
          case _GarminFile.maxMet:
            final d = r['calendarDate'] as String?;
            final v = r['vo2MaxValue'] as num?;
            if (d != null && v != null && v > 0) day(d)['vo2max'] = v;
          case _GarminFile.activities:
            activities.add(r);
          case _GarminFile.derived:
            break; // read above
        }
      }
    }

    Set<String> rawDays;
    try {
      rawDays = (await LocalDb.decodedRecTsMaxByDay()).keys.toSet();
    } catch (_) {
      rawDays = const {};
    }
    var written = 0, kept = 0, workouts = 0;
    for (final e in days.entries) {
      if (await LocalDb.isMeasuredDay(e.key)) {
        kept++;
        continue;
      }
      await _writeDay(e.key, e.value,
          ours: derived[e.key] ?? const {},
          finalized: !rawDays.contains(e.key));
      written++;
    }
    for (final a in activities) {
      if (await _writeActivity(a)) workouts++;
    }
    return GarminImportResult(written, workouts, kept);
  }

  static Iterable<Map<String, dynamic>> _records(
      Object? json, _GarminFile kind) sync* {
    if (json is Map<String, dynamic>) {
      // summarizedActivities: [{"summarizedActivitiesExport": [...]}]
      final inner = json['summarizedActivitiesExport'];
      if (inner is List) {
        yield* _records(inner, kind);
      } else {
        yield json;
      }
    } else if (json is List) {
      for (final x in json) {
        yield* _records(x, kind);
      }
    }
  }

  /// "2026-10-12T20:45:52.0" (GMT, no zone marker) → epoch seconds.
  static int? _gmtSec(Object? s) {
    if (s is! String) return null;
    final t = DateTime.tryParse(s.endsWith('Z') ? s : '${s}Z');
    return t == null ? null : t.millisecondsSinceEpoch ~/ 1000;
  }

  static Future<void> _writeDay(
    String date,
    Map<String, num?> f, {
    Map<String, double> ours = const {},
    required bool finalized,
  }) async {
    // Our resting HR (from the watch's 1-min HR) over Garmin's daily value.
    final rhr = ours['rhr'] ?? f['rhr'], rmssd = f['rmssd'], resp = f['resp'];
    final steps = f['steps'], vo2max = f['vo2max'];
    final tst = f['tst'];
    num? min(num? s) => s == null ? null : s / 60;
    Map<String, dynamic>? win, acct;
    if (tst != null) {
      final inBed = f['wake']! - f['onset']!;
      win = {
        'onset_ms': f['onset']! * 1000,
        'offset_ms': f['wake']! * 1000,
        'spt_sec': inBed,
      };
      acct = {
        'tst_sec': tst.round(),
        'in_bed_sec': inBed,
        'efficiency_pct': tst / inBed * 100,
        'light_sec': f['light']?.round(),
        'deep_sec': f['deep']?.round(),
        'rem_sec': f['rem']?.round(),
        'nrem_sec': (f['light'] != null && f['deep'] != null)
            ? (f['light']! + f['deep']!).round()
            : null,
        'wake_sec': f['awake']?.round(),
        'imported': true,
      };
    }
    Map<String, dynamic> env(Object v, {String tier = 'HIGH'}) => {
          'value': v,
          'confidence': 0.7,
          'tier': tier,
          'inputs_used': const ['garmin_export'],
        };
    final scalars = <String, double?>{
      'rhr': rhr?.toDouble(),
      'rmssd': rmssd?.toDouble(),
      'resp_rate': resp?.toDouble(),
      'steps': steps?.toDouble(),
      'vo2max': vo2max?.toDouble(),
      'tst_min': min(tst)?.toDouble(),
      'rem_min': min(f['rem'])?.toDouble(),
      'deep_min': min(f['deep'])?.toDouble(),
      'light_min': min(f['light'])?.toDouble(),
      'efficiency': (acct?['efficiency_pct'] as num?)?.toDouble(),
      ...ours,
    };
    final bundle = <String, dynamic>{
      'date': date,
      // `imported` keeps the day replaceable: the band's own measurement
      // always wins (LocalDb.isMeasuredDayRow).
      'imported': true,
      'source': 'garmin_export',
      'day_confidence': 0.7,
      'flags': [
        'IMPORTED_GARMIN',
        if (ours.isNotEmpty) 'DERIVED_FROM_GARMIN_RAW',
      ],
      'clinical': {
        if (rmssd != null) 'hrv_time': env({'rmssd': rmssd}),
        if (rhr != null) 'resting_hr': env({'low30Mean': rhr}),
      },
      if (acct != null)
        'sleep': {
          'window': env(win!),
          'accounting': env(acct, tier: 'ESTIMATE'),
        },
      'scalars': scalars,
    };
    await LocalDb.putDayResult(
      dayId: date,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(bundle),
      windowJson: jsonEncode(win ?? const {}),
      finalized: finalized,
      source: 'garmin_export',
      rhr: rhr?.toDouble(),
      rmssd: rmssd?.toDouble(),
      series: scalars,
    );
  }

  static Future<bool> _writeActivity(Map<String, dynamic> a) async {
    final garminType = a['activityType'] as String?;
    final id = a['activityId'];
    final startMs = a['startTimeGmt'] as num? ?? a['beginTimestamp'] as num?;
    final durMs = a['duration'] as num?;
    if (garminType == null || _skipTypes.contains(garminType)) return false;
    if (id == null || startMs == null || durMs == null || durMs <= 0) {
      return false;
    }
    final start = startMs ~/ 1000;
    final end = (startMs + durMs) ~/ 1000;
    final steps = a['steps'] as num?;
    await LocalDb.putSession({
      'id': 'garmin_$id',
      'start_ts': start,
      'end_ts': end,
      'type': _typeMap[garminType] ?? garminType,
      'status': 'done',
      'source': 'garmin',
      'calories': (a['calories'] as num?)?.toDouble(),
      'max_hr': (a['maxHr'] as num?)?.round(),
      'avg_hr': (a['avgHr'] as num?)?.round(),
      'steps': steps != null && steps > 0 ? steps.round() : null,
      'duration_min': (durMs / 60000).round(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    // No zone minutes: Garmin's zones are its own, not this app's.
    // Not exported to Health or Strava: Garmin Connect already sent these
    // workouts to both.
    return true;
  }
}
