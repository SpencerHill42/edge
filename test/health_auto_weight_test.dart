// Strap Cockpit: the weight follows Apple Health without a tap, but only
// after the store was read once by hand, and only when it actually changed.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/health/health_import_state.dart';
import 'package:openstrap_edge/health/health_profile_import.dart';

void main() {
  test('a new reading replaces the weight and keeps the rest', () {
    expect(weightUpdate({'weight_kg': 80.0, 'age': 40}, 78.4),
        {'weight_kg': 78.4, 'age': 40});
  });

  test('the same reading writes nothing', () {
    expect(weightUpdate({'weight_kg': 78.4}, 78.42), isNull);
  });

  test('no reading writes nothing, never a guess', () {
    expect(weightUpdate({'weight_kg': 78.4}, null), isNull);
  });

  test('an empty profile gets the reading', () {
    expect(weightUpdate(null, 78.4), {'weight_kg': 78.4});
  });

  test('never read by hand: no read at all, so no permission sheet',
      () async {
    final out = await autoWeightFromHealth({'weight_kg': 80.0},
        lastImport: (HealthImport _) async => null);
    expect(out, isNull);
  });
}
