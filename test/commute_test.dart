// Commute rides from the iPhone's activity log (lib/strava/commute.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/strava/commute.dart';
import 'package:openstrap_edge/strava/strava.dart';

void main() {
  const m = 60 * 1000;

  group('cycling spans from the activity log', () {
    test('a ride with a red light in the middle is one span', () {
      final spans = cyclingSpans([
        (startMs: 0, cycling: false, confidence: 2, automotive: false),
        (startMs: 10 * m, cycling: true, confidence: 2, automotive: false),
        (startMs: 18 * m, cycling: false, confidence: 1, automotive: false), // traffic light
        (startMs: 19 * m, cycling: true, confidence: 1, automotive: false),
        (startMs: 32 * m, cycling: false, confidence: 2, automotive: false),
      ], untilMs: 60 * m);
      expect(spans, [(startMs: 10 * m, endMs: 32 * m)]);
    });

    test('Armin\'s patchy ride home (1, 2, 8, 4 min, gaps up to 8) is one ride',
        () {
      final t0 = 17 * 60 * m;
      final spans = cyclingSpans([
        (startMs: t0 + 32 * m, cycling: true, confidence: 2, automotive: false),
        (startMs: t0 + 33 * m, cycling: false, confidence: 1, automotive: false),
        (startMs: t0 + 42 * m, cycling: true, confidence: 2, automotive: false),
        (startMs: t0 + 44 * m, cycling: false, confidence: 1, automotive: false),
        (startMs: t0 + 50 * m, cycling: true, confidence: 2, automotive: false),
        (startMs: t0 + 58 * m, cycling: false, confidence: 1, automotive: false),
        (startMs: t0 + 67 * m, cycling: true, confidence: 2, automotive: false),
        (startMs: t0 + 71 * m, cycling: false, confidence: 2, automotive: false),
      ], untilMs: t0 + 120 * m);
      expect(spans, [(startMs: t0 + 32 * m, endMs: t0 + 71 * m)]);
    });

    test('low confidence is not cycling, and a long stop splits two rides',
        () {
      final spans = cyclingSpans([
        (startMs: 0, cycling: true, confidence: 0, automotive: false),
        (startMs: 5 * m, cycling: true, confidence: 2, automotive: false),
        (startMs: 20 * m, cycling: false, confidence: 2, automotive: false),
        (startMs: 4 * 60 * m, cycling: true, confidence: 2, automotive: false),
        (startMs: 4 * 60 * m + 25 * m, cycling: false, confidence: 2, automotive: false),
      ], untilMs: 10 * 60 * m);
      expect(spans, [
        (startMs: 5 * m, endMs: 20 * m),
        (startMs: 4 * 60 * m, endMs: 4 * 60 * m + 25 * m),
      ]);
    });
  });

  group('what becomes a commute ride', () {
    CommuteVerdict v({
      int min = 20,
      int samples = 1200,
      double? hr = 112,
      bool overlap = false,
      int ageH = 1,
    }) =>
        commuteVerdict(
          durationSec: min * 60,
          hrSamples: samples,
          meanHr: hr,
          overlapsSession: overlap,
          ageSec: ageH * 3600,
        );

    test('a 20-minute ride with a raised pulse is saved', () {
      expect(v(), CommuteVerdict.save);
    });
    test('under 5 or over 60 minutes is not a commute (Wahoo has the tours)',
        () {
      expect(v(min: 3), CommuteVerdict.skip);
      expect(v(min: 75, samples: 4500), CommuteVerdict.skip);
    });
    test('an easy ride home at 76 bpm counts for a resting pulse of 45', () {
      expect(
          commuteVerdict(
              durationSec: 20 * 60,
              hrSamples: 1200,
              meanHr: 76,
              overlapsSession: false,
              ageSec: 3600,
              restingHr: 45),
          CommuteVerdict.save);
    });

    test('a car ride read as cycling: resting pulse, skipped', () {
      expect(v(hr: 68), CommuteVerdict.skip);
    });
    test('beats not synced yet: wait, but not for ever', () {
      expect(v(samples: 0, hr: null), CommuteVerdict.wait);
      expect(v(samples: 0, hr: null, ageH: 30), CommuteVerdict.skip);
    });
    test('a ride that was started by hand wins', () {
      expect(v(overlap: true), CommuteVerdict.skip);
    });
  });

  test('the U-Bahn home: cycling pieces with "in a vehicle" between, skipped',
      () {
    final log = <MotionChange>[
      (startMs: 0, cycling: true, confidence: 2, automotive: false),
      (startMs: 3 * m, cycling: false, confidence: 2, automotive: true),
      (startMs: 9 * m, cycling: true, confidence: 2, automotive: false),
      (startMs: 15 * m, cycling: false, confidence: 2, automotive: false),
    ];
    final span = cyclingSpans(log, untilMs: 60 * m).single;
    final vehicle = vehicleMsIn(log, span.startMs, span.endMs, untilMs: 60 * m);
    expect(vehicle, 6 * m);
    expect(
        commuteVerdict(
            durationSec: 15 * 60,
            hrSamples: 900,
            meanHr: 94,
            overlapsSession: false,
            ageSec: 3600,
            restingHr: 45,
            vehicleSec: vehicle ~/ 1000),
        CommuteVerdict.skip);
  });

  test('cycling goes to Strava as Ride', () {
    expect(stravaSportFor('Cycling')?.sportType, 'Ride');
  });
}
