import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/scan/scan_orientation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform Scan exit preserves the app orientation policy', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      const gateway = SystemScanOrientationGateway();

      await gateway.lockPortrait();
      await gateway.restore();

      expect(
        calls.map((call) => call.method),
        everyElement('SystemChrome.setPreferredOrientations'),
      );
      expect(calls[0].arguments, ['DeviceOrientation.portraitUp']);
      expect(
        calls[1].arguments,
        platform == TargetPlatform.android
            ? ['DeviceOrientation.portraitUp']
            : isEmpty,
        reason: platform == TargetPlatform.android
            ? 'Leaving Scan must not unlock landscape for the rest of Android.'
            : 'Leaving Scan must preserve the existing iPhone and iPad policy.',
      );
    });
  }
}
