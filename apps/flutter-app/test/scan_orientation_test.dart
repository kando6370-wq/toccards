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

  test(
    'system orientation gateway fixes Scan portrait and restores OS policy',
    () async {
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
      expect(calls[1].arguments, isEmpty);
    },
  );
}
