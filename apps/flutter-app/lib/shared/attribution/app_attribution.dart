import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singular_flutter_sdk/singular.dart';
import 'package:singular_flutter_sdk/singular_config.dart';

import 'singular_bootstrap.dart';

enum AppTrackingStatus {
  notDetermined,
  restricted,
  denied,
  authorized,
  notSupported,
}

abstract interface class AppTrackingGateway {
  Future<AppTrackingStatus> readStatus();
  Future<AppTrackingStatus> requestAuthorization();
}

abstract interface class AppAttributionGateway {
  Future<void> updateTrackingStatus(AppTrackingStatus status);
}

abstract interface class AppAttributionStartupStorage {
  Future<bool> claimFirstStartup();
}

class PreferencesAppAttributionStartupStorage
    implements AppAttributionStartupStorage {
  const PreferencesAppAttributionStartupStorage();

  static const _preparedKey = 'attribution.startup_prepared';

  @override
  Future<bool> claimFirstStartup() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_preparedKey) == true) return false;
    return preferences.setBool(_preparedKey, true);
  }
}

final appTrackingGatewayProvider = Provider<AppTrackingGateway>((ref) {
  return const PluginAppTrackingGateway();
});

final appAttributionGatewayProvider = Provider<AppAttributionGateway>((ref) {
  return SingularAttributionGateway();
});

final appAttributionStartupStorageProvider =
    Provider<AppAttributionStartupStorage>(
      (ref) => const PreferencesAppAttributionStartupStorage(),
    );

final appAttributionCoordinatorProvider = Provider<AppAttributionCoordinator>((
  ref,
) {
  return AppAttributionCoordinator(
    tracking: ref.watch(appTrackingGatewayProvider),
    attribution: ref.watch(appAttributionGatewayProvider),
    startupStorage: ref.watch(appAttributionStartupStorageProvider),
  );
});

class AppAttributionCoordinator {
  AppAttributionCoordinator({
    required AppTrackingGateway tracking,
    required AppAttributionGateway attribution,
    required AppAttributionStartupStorage startupStorage,
  }) : _tracking = tracking,
       _attribution = attribution,
       _startupStorage = startupStorage;

  final AppTrackingGateway _tracking;
  final AppAttributionGateway _attribution;
  final AppAttributionStartupStorage _startupStorage;
  bool? _firstStartup;
  Future<void>? _startupMarkerPreload;
  Future<void>? _startup;

  Future<void> preloadStartupMarker() {
    return _startupMarkerPreload ??= _preloadStartupMarker();
  }

  Future<void> _preloadStartupMarker() async {
    _firstStartup = await _claimFirstStartup();
  }

  Future<void> prepareForStartup({required bool allowInitialRequest}) {
    return _startup ??= _prepare(allowInitialRequest: allowInitialRequest);
  }

  Future<void> _prepare({required bool allowInitialRequest}) async {
    var status = await _readStatus();
    if (_firstStartup == null) await preloadStartupMarker();
    if (allowInitialRequest &&
        (_firstStartup ?? false) &&
        status == AppTrackingStatus.notDetermined) {
      try {
        status = await _tracking.requestAuthorization();
      } on Object {
        // ATT failures must not block onboarding or any product capability.
      }
    }
    await _updateAttribution(status);
  }

  Future<bool> _claimFirstStartup() async {
    try {
      return await _startupStorage.claimFirstStartup();
    } on Object {
      return false;
    }
  }

  Future<void> refreshWithoutPrompt() async {
    final startup = _startup;
    if (startup == null) return;
    await startup;
    final status = await _readStatus();
    await _updateAttribution(status);
  }

  Future<AppTrackingStatus> _readStatus() async {
    try {
      return await _tracking.readStatus();
    } on Object {
      return AppTrackingStatus.notSupported;
    }
  }

  Future<void> _updateAttribution(AppTrackingStatus status) async {
    try {
      await _attribution.updateTrackingStatus(status);
    } on Object {
      // Attribution is supplementary and must never interrupt the App flow.
    }
  }
}

class PluginAppTrackingGateway implements AppTrackingGateway {
  const PluginAppTrackingGateway();

  @override
  Future<AppTrackingStatus> readStatus() async {
    return _mapStatus(
      await AppTrackingTransparency.trackingAuthorizationStatus,
    );
  }

  @override
  Future<AppTrackingStatus> requestAuthorization() async {
    return _mapStatus(
      await AppTrackingTransparency.requestTrackingAuthorization(),
    );
  }

  AppTrackingStatus _mapStatus(TrackingStatus status) => switch (status) {
    TrackingStatus.notDetermined => AppTrackingStatus.notDetermined,
    TrackingStatus.restricted => AppTrackingStatus.restricted,
    TrackingStatus.denied => AppTrackingStatus.denied,
    TrackingStatus.authorized => AppTrackingStatus.authorized,
    TrackingStatus.notSupported => AppTrackingStatus.notSupported,
  };
}

class SingularAttributionGateway implements AppAttributionGateway {
  SingularAttributionGateway({
    Future<SingularCredentials?> Function() loadCredentials =
        loadSingularCredentials,
  }) : _credentials = loadCredentials();

  final Future<SingularCredentials?> _credentials;
  var _started = false;

  @override
  Future<void> updateTrackingStatus(AppTrackingStatus status) async {
    final credentials = await _credentials;
    if (credentials == null) return;
    final limitDataSharing = switch (status) {
      AppTrackingStatus.denied ||
      AppTrackingStatus.restricted ||
      AppTrackingStatus.notDetermined => true,
      AppTrackingStatus.authorized || AppTrackingStatus.notSupported => false,
    };
    if (!_started) {
      final config = SingularConfig(credentials.apiKey, credentials.secretKey)
        ..limitDataSharing = limitDataSharing
        ..waitForTrackingAuthorizationWithTimeoutInterval = 0;
      Singular.start(config);
      _started = true;
      return;
    }
    Singular.limitDataSharing(limitDataSharing);
  }
}

class AppAttributionLifecycleObserver extends ConsumerStatefulWidget {
  const AppAttributionLifecycleObserver({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppAttributionLifecycleObserver> createState() =>
      _AppAttributionLifecycleObserverState();
}

class _AppAttributionLifecycleObserverState
    extends ConsumerState<AppAttributionLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(appAttributionCoordinatorProvider).refreshWithoutPrompt(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
