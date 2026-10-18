// Commute rides from the iPhone's activity log (lib/strava/commute.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/strava/commute.dart';
import 'package:openstrap_edge/strava/strava.dart';

void main() {
  const m = 60 * 1000;

  group('cycling spans from the activity log', () {
    test('a ride with a red light in the middle is one span', () {
      final spans = cyclingSpans([
        (startMs: 0, cycling: false, confidence: 2),
        (startMs: 10 * m, cycling: true, confidence: 2),
        (startMs: 18 * m, cycling: false, confidence: 1), // traffic light
        (startMs: 19 * m, cycling: true, confidence: 1),
        (startMs: 32 * m, cycling: false, confidence: 2),
      ], untilMs: 60 * m);
      expect(spans, [(startMs: 10 * m, endMs: 32 * m)]);
    });

    test('low confidence is not cycling, and a long stop splits two rides',
        () {
      final spans = cyclingSpans([
        (startMs: 0, cycling: true, confidence: 0),
        (startMs: 5 * m, cycling: true, confidence: 2),
        (startMs: 20 * m, cycling: false, confidence: 2),
        (startMs: 4 * 60 * m, cycling: true, confidence: 2),
        (startMs: 4 * 60 * m + 25 * m, cycling: false, confidence: 2),
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

  test('cycling goes to Strava as Ride', () {
    expect(stravaSportFor('Cycling')?.sportType, 'Ride');
  });
}
