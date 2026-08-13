import 'package:kando_app/shared/attribution/app_attribution.dart';

AppAttributionCoordinator testAppAttributionCoordinator() {
  return AppAttributionCoordinator(
    tracking: const _TestTrackingGateway(),
    attribution: const _TestAttributionGateway(),
    startupStorage: const _TestStartupStorage(),
  );
}

class _TestTrackingGateway implements AppTrackingGateway {
  const _TestTrackingGateway();

  @override
  Future<AppTrackingStatus> readStatus() async =>
      AppTrackingStatus.notSupported;

  @override
  Future<AppTrackingStatus> requestAuthorization() async =>
      AppTrackingStatus.notSupported;
}

class _TestAttributionGateway implements AppAttributionGateway {
  const _TestAttributionGateway();

  @override
  Future<void> updateTrackingStatus(AppTrackingStatus status) async {}
}

class _TestStartupStorage implements AppAttributionStartupStorage {
  const _TestStartupStorage();

  @override
  Future<bool> claimFirstStartup() async => false;
}
