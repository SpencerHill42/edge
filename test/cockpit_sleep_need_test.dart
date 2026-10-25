// Strap Cockpit's sleep need baseline: the median of the free nights, and the
// debt as the net shortfall of the recent nights against it.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/crossday_pipeline.dart';

void main() {
  test('median of free nights, net 7-night shortfall', () {
    // Armin's weekends: long catch-up nights pull the p75 to ~9.3 h.
    final free = [7.0, 7.9, 8.1, 8.3, 9.3, 9.6, 10.4];
    final recent = [7.0, 7.5, 7.1, 8.6, 7.4, 7.0, 7.3];
    final m = cockpitSleepDebt(recent, free);
    expect(m.value!.osdHours, 8.3);
    // (8.3 × 7) − 51.9 = 6.2 h short over the week; the need caps it at 1 h.
    expect(m.value!.debtHours, closeTo(6.2, 1e-9));
    expect(m.confidence, 0.85);
  });

  test('long nights pay the debt back, never below zero', () {
    final m = cockpitSleepDebt([9.0, 9.0, 9.0], [8.0, 8.0, 8.0, 8.0]);
    expect(m.value!.debtHours, 0);
  });

  test('no free night: no baseline, no guess', () {
    final m = cockpitSleepDebt([7.0, 7.0, 7.0], const []);
    expect(m.value!.osdHours, isNull);
    expect(m.confidence, 0.3);
  });

  test('a sleep goal is the baseline, no free nights needed', () {
    final m = cockpitSleepDebt([7.5, 8.0, 7.0], const [], goal: 8);
    expect(m.value!.osdHours, 8);
    expect(m.value!.debtHours, closeTo(1.5, 1e-9));
    expect(m.confidence, 0.85);
  });
}
