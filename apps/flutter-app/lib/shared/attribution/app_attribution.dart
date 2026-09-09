import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
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

abstract interface class AppAttributionEventReporter {
  Future<void> trackRevenue({
    required String eventName,
    required String currency,
    required double value,
    required String transactionId,
    required String productId,
  });
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

final singularAttributionGatewayProvider = Provider<SingularAttributionGateway>(
  (ref) {
    final gateway = SingularAttributionGateway();
    ref.onDispose(gateway.dispose);
    return gateway;
  },
);

final appAttributionGatewayProvider = Provider<AppAttributionGateway>((ref) {
  return ref.watch(singularAttributionGatewayProvider);
});

final appAttributionEventReporterProvider =
    Provider<AppAttributionEventReporter>((ref) {
      return ref.watch(singularAttributionGatewayProvider);
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

class SingularAttributionGateway
    implements AppAttributionGateway, AppAttributionEventReporter {
  SingularAttributionGateway({
    Future<SingularCredentials?> Function() loadCredentials =
        loadSingularCredentials,
  }) : _loadCredentials = loadCredentials {
    unawaited(_readCredentials());
  }

  final Future<SingularCredentials?> Function() _loadCredentials;
  SingularCredentials? _credentials;
  Future<SingularCredentials?>? _credentialsRequest;
  final _ready = Completer<void>();
  Future<void> get initialized => _ready.future;

  static const _retrySeconds = [5, 15, 30, 60];
  Timer? _retryTimer;
  var _retryAttempt = 0;
  var _foreground = true;
  var _disposed = false;
  var _started = false;
  AppTrackingStatus? _trackingStatus;

  Future<SingularCredentials?> _readCredentials() {
    if (_disposed) return Future.value(null);
    if (_credentials != null) return Future.value(_credentials);
    return _credentialsRequest ??= _fetchCredentials().whenComplete(() {
      _credentialsRequest = null;
    });
  }

  Future<SingularCredentials?> _fetchCredentials() async {
    try {
      return _credentials = await _loadCredentials();
    } on Object {
      // Do not log the request or credentials. A failure remains retryable.
      debugPrint('Unable to load Singular runtime configuration.');
      return null;
    }
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (!foreground) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    // Resume uses updateTrackingStatus after rereading ATT without a prompt.
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  Future<void> updateTrackingStatus(AppTrackingStatus status) async {
    _trackingStatus = status;
    await _attemptInitialization();
  }

  Future<void> _attemptInitialization() async {
    if (_disposed || !_foreground || _trackingStatus == null) return;
    try {
      final credentials = await _readCredentials();
      if (_disposed || !_foreground) return;
      if (credentials == null) {
        debugPrint(
          'Singular attribution unavailable: runtime configuration will retry.',
        );
        _scheduleRetry();
        return;
      }
      // Concurrent callers share the request and use the latest ATT choice.
      final limitDataSharing = switch (_trackingStatus!) {
        AppTrackingStatus.denied ||
        AppTrackingStatus.restricted ||
        AppTrackingStatus.notDetermined => true,
        AppTrackingStatus.authorized || AppTrackingStatus.notSupported => false,
      };
      if (!_started) {
        final config = SingularConfig(credentials.apiKey, credentials.secretKey)
          ..limitDataSharing = limitDataSharing
          ..waitForTrackingAuthorizationWithTimeoutInterval = 0
          ..logLevel = kDebugMode ? 5 : -1;
        Singular.start(config);
        _started = true;
        _retryTimer?.cancel();
        _retryTimer = null;
        _ready.complete();
        debugPrint('Singular attribution SDK initialized.');
      } else {
        Singular.limitDataSharing(limitDataSharing);
      }
    } on Object {
      debugPrint('Unable to initialize or update Singular attribution.');
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_disposed || !_foreground || _started || _retryTimer != null) return;
    final seconds = _retrySeconds[_retryAttempt];
    if (_retryAttempt < _retrySeconds.length - 1) _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      unawaited(_attemptInitialization());
    });
  }

  @override
  Future<void> trackRevenue({
    required String eventName,
    required String currency,
    required double value,
    required String transactionId,
    required String productId,
  }) async {
    if (_disposed) throw StateError('Singular attribution has been disposed.');
    if (!_started && _trackingStatus != null) {
      await _attemptInitialization();
      if (!_started) {
        throw StateError(
          'Singular revenue unavailable: initialization pending.',
        );
      }
    } else if (!_started && await _readCredentials() == null) {
      throw StateError('Singular revenue unavailable: missing credentials.');
    }
    // Startup retries may reach the reporter before the ATT flow finishes.
    await _ready.future;
    if (_disposed) throw StateError('Singular attribution has been disposed.');
    // SDK 1.9.0 returns void; completion means handoff, not server delivery.
    runZonedGuarded(
      () => Singular.customRevenueWithAttributes(eventName, currency, value, {
        'transaction_id': transactionId,
        'product_id': productId,
      }),
      (error, stackTrace) => debugPrint(
        'Unable to hand Singular revenue to the platform: $error\n$stackTrace',
      ),
    );
    debugPrint('Singular revenue handed to SDK: $eventName');
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
      ref.read(singularAttributionGatewayProvider).setForeground(true);
      unawaited(
        ref.read(appAttributionCoordinatorProvider).refreshWithoutPrompt(),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ref.read(singularAttributionGatewayProvider).setForeground(false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
