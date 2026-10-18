// Weight and body-fat trend (docs/TODO.md 6b): the change over N days and the
// import of the scale's readings.
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:openstrap_edge/health/health_measurement_import.dart';
import 'package:openstrap_edge/ui2/screens/body_trend.dart';

HealthDataPoint _p(HealthDataType t, double v, String id) => HealthDataPoint(
      uuid: id,
      value: NumericHealthValue(numericValue: v),
      type: t,
      unit: HealthDataUnit.NO_UNIT,
      dateFrom: DateTime(2026, 10, 1),
      dateTo: DateTime(2026, 10, 1),
      sourcePlatform: HealthPlatformType.appleHealth,
      sourceDeviceId: 'd',
      sourceId: 's',
      sourceName: 'Garmin Connect',
    );

void main() {
  const day = 86400, now = 1792300000;

  test('change over 30 days: newest minus the reading closest before', () {
    final r = [
      (ts: now - 40 * day, value: 80.0, source: 'Garmin'),
      (ts: now - 31 * day, value: 79.5, source: 'Garmin'),
      (ts: now - 2 * day, value: 78.0, source: 'Garmin'),
    ];
    expect(bodyChange(r, 30, nowSec: now), closeTo(-1.5, 1e-9));
  });

  test('no change when the history does not reach that far back', () {
    final r = [
      (ts: now - 20 * day, value: 80.0, source: 'Garmin'),
      (ts: now - 1 * day, value: 79.0, source: 'Garmin'),
    ];
    expect(bodyChange(r, 30, nowSec: now), isNull);
    expect(bodyChange(r.sublist(1), 30, nowSec: now), isNull);
  });

  test('the scale\'s weight and body fat are imported, fat as a percent', () {
    final rows = rowsFrom([
      _p(HealthDataType.WEIGHT, 78.4, 'a'),
      _p(HealthDataType.BODY_FAT_PERCENTAGE, 0.183, 'b'),
      _p(HealthDataType.WEIGHT, 5, 'c'), // a bad record, dropped
    ]);
    expect(rows.map((r) => r['kind']), [kKindWeight, kKindBodyFat]);
    expect(rows[1]['value'] as double, closeTo(18.3, 1e-9));
    expect(rows.first['source'], 'Garmin Connect');
  });
}
