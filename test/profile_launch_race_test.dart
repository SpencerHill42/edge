// TODO 3b: at launch the Health weight sync could save the profile before it
// was loaded, so it was stored as the weight alone and age and sex were gone
// (Belastung empty). A write before the load merges onto what is stored.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a weight saved before the profile loads keeps age and sex', () async {
    SharedPreferences.setMockInitialValues({
      'local_profile_json':
          jsonEncode({'weight_kg': 74.5, 'age': 31, 'sex': 'm', 'height_cm': 180.0}),
    });
    final app = AppState.forTesting(); // never runs the load
    expect(app.user, isNull);

    await app.updateProfile({'weight_kg': 74.2});

    final stored = jsonDecode(
        (await SharedPreferences.getInstance()).getString('local_profile_json')!);
    for (final p in [app.user!, stored]) {
      expect(p['weight_kg'], 74.2);
      expect(p['age'], 31);
      expect(p['sex'], 'm');
      expect(p['height_cm'], 180.0);
    }
  });
}
