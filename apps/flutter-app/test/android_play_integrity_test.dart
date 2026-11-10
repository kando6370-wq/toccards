import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/android_play_integrity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'development Android defers integrity only to the server-controlled bypass',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final evidence = await const MethodChannelAndroidPlayIntegrity()
          .createEvidence(deviceId: 'device-1');

      expect(evidence, isNotNull);
      expect(evidence?.token, isNull);
      expect(evidence?.requestNonce, isNotEmpty);
    },
  );
}
