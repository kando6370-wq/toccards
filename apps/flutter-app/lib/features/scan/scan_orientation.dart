import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ScanOrientationGateway {
  Future<void> lockPortrait();
  Future<void> restore();
}

final scanOrientationGatewayProvider = Provider<ScanOrientationGateway>(
  (ref) => const SystemScanOrientationGateway(),
);

class SystemScanOrientationGateway implements ScanOrientationGateway {
  const SystemScanOrientationGateway();

  @override
  Future<void> lockPortrait() => SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  @override
  Future<void> restore() =>
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
}
