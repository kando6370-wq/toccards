import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'app preferences keep completion across restarts within one installation',
    () async {
      SharedPreferences.setMockInitialValues({});

      const firstLaunch = PreferencesOnboardingStorage();
      expect(await firstLaunch.readCompleted(), isFalse);

      await firstLaunch.writeCompleted();

      const restartedApp = PreferencesOnboardingStorage();
      expect(await restartedApp.readCompleted(), isTrue);
    },
  );
}
