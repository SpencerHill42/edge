// Garmin Connect export → days + sessions, over the real LocalDb.
//
// The point of the import is that the app is trained from day one, so the
// imported resting HR has to reach the MEASURED-ONLY series the baselines
// read, while a day the band measured is never overwritten.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart' show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/import/garmin_import.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_garmin_import_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    tmp = Directory.systemTemp.createTempSync('garmin_import_test');
  });

  tearDownAll(() async {
    await LocalDb.close();
    tmp.deleteSync(recursive: true);
  });

  test('imports sleep, HRV, RHR, steps, VO2max and workouts', () async {
    // 2026-10-03 the band already measured.
    await LocalDb.putDayResult(
      dayId: '2026-10-03',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({'date': '2026-10-03', 'scalars': {'rhr': 50}}),
      windowJson: '{}',
      source: 'band',
      rhr: 50,
      series: const {'rhr': 50},
    );

    Map<String, dynamic> sleep(String date, String on, String off) => {
          'sleepStartTimestampGMT': on,
          'sleepEndTimestampGMT': off,
          'calendarDate': date,
          'deepSleepSeconds': 3600,
          'lightSleepSeconds': 14400,
          'remSleepSeconds': 7200,
          'awakeSleepSeconds': 1800,
          'averageRespiration': 15.0,
        };
    final files = <String, Object>{
      'DI_CONNECT/DI-Connect-Wellness/2026-09-01_2026-10-05_1_sleepData.json': [
        sleep('2026-10-02', '2026-10-01T21:00:00.0', '2026-10-02T05:00:00.0'),
        sleep('2026-10-03', '2026-10-02T21:00:00.0', '2026-10-03T05:00:00.0'),
        {'retro': false},
      ],
      'DI_CONNECT/DI-Connect-Wellness/2026-09-01_2026-10-05_1_healthStatusData.json':
          [
        {
          'calendarDate': '2026-10-02',
          'metrics': [
            {'type': 'HRV', 'value': 70.0},
            {'type': 'HR', 'value': 54.0},
          ],
        },
      ],
      'DI_CONNECT/DI-Connect-Aggregator/UDSFile_2026-09-01_2026-10-05.json': [
        {
          'calendarDate': '2026-10-02',
          'totalSteps': 9000,
          'restingHeartRate': 46,
          'currentDayRestingHeartRate': 48,
        },
      ],
      'DI_CONNECT/DI-Connect-Metrics/MetricsMaxMetData_20260901_20261005_1.json':
          [
        {'calendarDate': '2026-10-02', 'vo2MaxValue': 55.0},
      ],
      'DI_CONNECT/DI-Connect-Fitness/x_1_summarizedActivities.json': [
        {
          'summarizedActivitiesExport': [
            {
              'activityId': 1,
              'activityType': 'paddelball',
              'startTimeGmt': 1790946000000.0,
              'duration': 3600000.0,
              'avgHr': 140.0,
              'maxHr': 175.0,
              'calories': 600.0,
            },
            {
              'activityId': 2,
              'activityType': 'motorcycling_v2',
              'startTimeGmt': 1790950000000.0,
              'duration': 3600000.0,
            },
          ],
        },
      ],
      'DI_CONNECT/DI-Connect-Uploaded-Files/ignored.json': {'x': 1},
      // Our engine's numbers off the watch's 1-min HR: they win on rhr and
      // add strain; anything outside the allowed keys is dropped.
      'turbo_garmin_derived.json': {
        '2026-10-02': {'rhr': 47.0, 'strain': 9.5, 'trimp': 120.0, 'tst_min': 1.0},
        '2026-10-03': {'strain': 3.0},
      },
    };
    final archive = Archive();
    for (final e in files.entries) {
      archive.addFile(ArchiveFile.bytes(e.key, utf8.encode(jsonEncode(e.value))));
    }
    final zip = File(p.join(tmp.path, 'garmin.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    final csv = File(p.join(tmp.path, 'x.csv'))..writeAsStringSync('a,b\n1,2\n');

    expect(await GarminImporter.isGarminExport(zip.path), isTrue);
    expect(await GarminImporter.isGarminExport(csv.path), isFalse);

    final r = await GarminImporter.importFiles([zip.path]);
    expect(r.days, 1);
    expect(r.skippedExistingDays, 1);
    expect(r.workouts, 1);

    // The measured day is untouched.
    final band = await LocalDb.dayResult('2026-10-03');
    expect(jsonDecode(band!['payload_json'] as String)['source'], isNull);

    // The Garmin day is replaceable by the band, yet feeds the baselines.
    expect(await LocalDb.isMeasuredDay('2026-10-02'), isFalse);
    expect(await LocalDb.importedDates(), isNot(contains('2026-10-02')));
    final rhr = await LocalDb.metricSeries('rhr', measuredOnly: true);
    expect(
      rhr.where((x) => x['date'] == '2026-10-02').single['value'],
      47, // ours over Garmin's daily value
    );
    final day = jsonDecode(
        (await LocalDb.dayResult('2026-10-02'))!['payload_json'] as String);
    final s = day['scalars'] as Map;
    expect(s['rmssd'], 70);
    expect(s['steps'], 9000);
    expect(s['vo2max'], 55);
    expect(s['tst_min'], 420);
    expect(s['resp_rate'], 15);
    expect(s['strain'], 9.5);
    expect(s['trimp'], 120);
    expect(s['tst_min'], 420, reason: 'sleep stays Garmin\'s');
    expect(day['flags'], contains('DERIVED_FROM_GARMIN_RAW'));
    final strain = await LocalDb.metricSeries('strain', measuredOnly: true);
    expect(strain.where((x) => x['date'] == '2026-10-02').single['value'], 9.5);
    // A band-measured day keeps its own numbers.
    expect(strain.where((x) => x['date'] == '2026-10-03'), isEmpty);

    final session = await LocalDb.session('garmin_1');
    expect(session!['type'], 'padel');
    expect(session['avg_hr'], 140);
    expect(session['duration_min'], 60);
    expect(await LocalDb.session('garmin_2'), isNull);
  });
}
