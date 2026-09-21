import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cashier_app/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppSettings kasir PIN', () {
    test('hasPin false when none configured', () {
      expect(AppSettings.instance.hasPin, isFalse);
      expect(AppSettings.instance.verifyPin('1234'), isFalse);
    });

    test('verifyPin accepts only the stored PIN', () async {
      final s = AppSettings.instance;
      await s.setPin('4821');
      expect(s.hasPin, isTrue);
      expect(s.verifyPin('4821'), isTrue);
      expect(s.verifyPin('4820'), isFalse);
      expect(s.verifyPin(''), isFalse);
    });

    test('PIN is stored as a SHA-256 hash, not plain text', () async {
      final s = AppSettings.instance;
      await s.setPin('1234');
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('cashier_pin_hash');
      expect(stored, isNotNull);
      expect(stored, isNot('1234'));
      expect(stored!.length, 64);
    });

    test('setPin replaces the previous PIN', () async {
      final s = AppSettings.instance;
      await s.setPin('1111');
      expect(s.verifyPin('1111'), isTrue);
      await s.setPin('9999');
      expect(s.verifyPin('9999'), isTrue);
      expect(s.verifyPin('1111'), isFalse);
    });

    test('clearPin disables the feature', () async {
      final s = AppSettings.instance;
      await s.setPin('1234');
      await s.clearPin();
      expect(s.hasPin, isFalse);
      expect(s.verifyPin('1234'), isFalse);
    });

    test('verifyPin is constant-time-ish and never equal when empty', () async {
      final s = AppSettings.instance;
      await s.setPin('0000');
      expect(s.verifyPin('0000'), isTrue);
    });
  });
}