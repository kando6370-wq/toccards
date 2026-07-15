import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';

void main() {
  test(
    'secure storage keeps onboarding completion because the first-launch decision must survive app restarts',
    () async {
      FlutterSecureStorage.setMockInitialValues({});

      const firstLaunch = SecureOnboardingStorage();
      expect(await firstLaunch.readCompleted(), isFalse);

      await firstLaunch.writeCompleted();

      const restartedApp = SecureOnboardingStorage();
      expect(await restartedApp.readCompleted(), isTrue);
    },
  );
}
