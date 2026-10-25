// Replay a Garmin export's health FIT files through the REAL Garmin path
// (adapter, host, sqlite) and derive every day with our engine, so a watch's
// history can be read in our own numbers next to Garmin's.
//
// Skipped unless GARMIN_MANIFEST points at a JSON list of
// [path, sub-type (32/49/68), time_created unix], oldest first. Writes one
// JSON object per day to GARMIN_OUT. GARMIN_DAYS limits the run to the
// newest N days. No personal data lives in the repo.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/garmin_link.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/inputs/canonical.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/garmin_watch.dart';

const _dev = 'garmin-history';

String _label(int unix) {
  final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

void main() {
  final env = Platform.environment;
  final manifest = env['GARMIN_MANIFEST'];
  test('replay a Garmin export and derive every day', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = 'garmin_history_replay.db';
    await databaseFactory.deleteDatabase(
        p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName));
    await LocalDb.upsertDevice(
        id: _dev, adapterId: 'garmin', remoteId: 'AA:BB:CC:00:00:09',
        label: 'garmin');

    var rows = [
      for (final r in jsonDecode(File(manifest!).readAsStringSync()) as List)
        (r[0] as String, r[1] as int, r[2] as int),
    ];
    final limit = int.tryParse(env['GARMIN_DAYS'] ?? '');
    if (limit != null) {
      final from = rows.last.$3 - limit * 86400;
      rows = [for (final r in rows) if (r.$3 >= from) r];
    }

    // Small sessions: the replay harness serves one bounded session at a time.
    const batch = 25;
    var index = 1;
    for (var i = 0; i < rows.length; i += batch) {
      final files = <int, (int, int, Uint8List)>{};
      for (final (path, sub, ts) in rows.skip(i).take(batch)) {
        files[index++] = (sub, ts, File(path).readAsBytesSync());
      }
      final now = rows.skip(i).take(batch).last.$3 + 3600;
      await GarminLink.instance.ingestForTest(
          _dev, GarminWatchScript(files, chunk: 2000).reply,
          nowSeconds: () => now);
      if ((i ~/ batch) % 20 == 0) {
        // ignore: avoid_print
        print('ingested ${i + files.length}/${rows.length}');
      }
    }

    await LocalDb.setCursor(kActiveWearableCursor, _dev);
    await LocalDb.setCursor(wearableEnabledCursor('garmin'), '1');
    final days = <String>{
      for (final r in rows) _label(r.$3),
    }.toList()
      ..sort();
    final profile = Profile(
        ageYears: int.tryParse(env['GARMIN_AGE'] ?? '') ?? 31,
        weightKg: 74.5,
        heightCm: 180,
        sex: 'm');
    // Oldest first, in weeks, so each week's baselines see the weeks before.
    // The cross-day bundle (sleep need, load) is read right after its week:
    // [crossDayAsOf] only reaches back over the stored 90-day input.
    final cross = <String, Map>{};
    for (var i = 0; i < days.length; i += 7) {
      final week = days.skip(i).take(7).toList();
      await DerivationEngine().runDays(profile, week.toSet(), force: true);
      for (final d in week) {
        cross[d] = await crossDayAsOf(d);
      }
    }

    final out = File(env['GARMIN_OUT'] ?? 'garmin_history.jsonl').openWrite();
    for (final d in days) {
      final row = await LocalDb.dayResult(d);
      if (row == null) continue;
      final payload = jsonDecode(row['payload_json'] as String) as Map;
      out.writeln(jsonEncode({
        'date': d,
        'scalars': payload['scalars'],
        'hr_sleep_window': payload['hr_sleep_window'],
        'cells': await dayCells(d),
        'crossday': cross[d],
      }));
    }
    await out.close();
    await LocalDb.close();
  }, skip: manifest == null ? 'set GARMIN_MANIFEST' : false,
      timeout: const Timeout(Duration(hours: 6)));
}
