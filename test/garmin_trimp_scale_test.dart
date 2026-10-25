// Garmin-export TRIMP (1-min HR) is scaled to the band's level by the
// window's medians, and only once there are 7 band days.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';

void main() {
  List<Map<String, dynamic>> days(int band) => [
        for (var i = 0; i < 10; i++) {'date': 'g$i', 'trimp': 100.0},
        for (var i = 0; i < band; i++) {'date': 'b$i', 'trimp': 150.0},
      ];
  final garmin = {for (var i = 0; i < 10; i++) 'g$i'};

  test('scaled by the ratio of medians', () {
    final d = days(7);
    scaleGarminTrimp(d, garmin);
    expect(d.first['trimp'], closeTo(150, 1e-9));
    expect(d.last['trimp'], 150, reason: 'band days untouched');
  });

  test('too few band days: unchanged', () {
    final d = days(6);
    scaleGarminTrimp(d, garmin);
    expect(d.first['trimp'], 100);
  });
}
