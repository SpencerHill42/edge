// The "around the blood draw" read: the week up to the draw against the
// usual of the 60 days before, and nothing invented where data is missing.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/lab_detail.dart';

String _d(DateTime x) =>
    '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

void main() {
  final draw = DateTime(2024, 12, 16);
  List<({String date, double v})> days(int from, int to, double v) => [
        for (var i = from; i <= to; i++)
          (date: _d(DateTime(draw.year, draw.month, draw.day - i)), v: v),
      ];

  test('week mean up to the draw, usual median before it', () {
    final s = [...days(0, 6, 52), ...days(7, 66, 46)];
    final a = sensorAround(s, '2024-12-16');
    expect(a.week, 52);
    expect(a.usual, 46);
  });

  test('days after the draw do not count', () {
    final s = [
      (date: '2024-12-17', v: 90.0),
      ...days(0, 0, 50),
    ];
    expect(sensorAround(s, '2024-12-16').week, 50);
  });

  test('no history: nothing, not a guess', () {
    final a = sensorAround(days(0, 2, 50), '2024-12-16');
    expect(a.week, 50);
    expect(a.usual, isNull); // under a week of prior days
    expect(sensorAround(const [], '2023-04-24').week, isNull);
  });
}
