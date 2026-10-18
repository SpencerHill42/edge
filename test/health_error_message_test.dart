// docs/TODO.md item 2: a Health request that THREW is reported as a failure
// with its reason, never as "you did not grant it".
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/health/health_import_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => lastHealthError = null);

  test('no failure: the caller\'s "not granted" text', () {
    lastHealthError = null;
    expect(healthNotGranted(null, 'not granted'), 'not granted');
  });

  test('a thrown request: the reason, and not "not granted"', () {
    noteHealthError(
        'health_profile',
        PlatformException(
            code: 'HKError',
            message: 'Missing com.apple.developer.healthkit entitlement.'));
    final s = healthNotGranted(null, 'not granted');
    expect(s, contains('Missing com.apple.developer.healthkit entitlement.'));
    expect(s, isNot('not granted'));
  });
}
