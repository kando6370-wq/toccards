import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_environment.dart';
import '../firebase/app_firebase.dart';
import 'analytics_events.dart';
import 'mixpanel_bootstrap.dart';

final analyticsProvider = Provider<AppAnalytics>((ref) {
  return AppAnalytics.disabled();
});

class AppAnalytics {
  AppAnalytics._({
    required Mixpanel? mixpanel,
    required AppFirebase? firebase,
    required String appVersion,
    required bool isDebugData,
    bool mixpanelInitializationPending = false,
    bool initialIdentityPending = false,
    void Function(String event, Map<String, Object?> properties)? eventObserver,
    void Function(String event, Map<String, Object?> properties)?
    firebaseEventObserver,
  }) : _mixpanel = mixpanel,
       _firebase = firebase,
       _appVersion = appVersion,
       _isDebugData = isDebugData,
       _mixpanelInitializationPending = mixpanelInitializationPending,
       _initialIdentityPending = initialIdentityPending,
       _eventObserver = eventObserver,
       _firebaseEventObserver = firebaseEventObserver;

  factory AppAnalytics.disabled() {
    return AppAnalytics._(
      mixpanel: null,
      firebase: null,
      appVersion: '',
      isDebugData: true,
    );
  }

  @visibleForTesting
  factory AppAnalytics.recording(
    void Function(String event, Map<String, Object?> properties) onEvent, {
    void Function(String event, Map<String, Object?> properties)?
    onFirebaseEvent,
  }) {
    return AppAnalytics._(
      mixpanel: null,
      firebase: null,
      appVersion: '',
      isDebugData: true,
      eventObserver: onEvent,
      firebaseEventObserver: onFirebaseEvent,
    );
  }

  @visibleForTesting
  factory AppAnalytics.initializingForTest(
    Future<Mixpanel?> initialization, {
    String appVersion = '1.0.1',
  }) {
    final analytics = AppAnalytics._(
      mixpanel: null,
      firebase: null,
      appVersion: appVersion,
      isDebugData: true,
      mixpanelInitializationPending: true,
      initialIdentityPending: true,
    );
    unawaited(analytics._completeMixpanelInitialization(initialization));
    return analytics;
  }

  static AppAnalytics initialize({AppFirebase? firebase}) {
    final analytics = AppAnalytics._(
      mixpanel: null,
      firebase: firebase,
      appVersion: '',
      isDebugData: AppConfig.isDebugData,
      mixpanelInitializationPending: true,
      initialIdentityPending: true,
    );
    final appVersionReady = analytics._loadAppVersion();
    unawaited(analytics._initializeMixpanel(appVersionReady));
    return analytics;
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
    } on Object {
      // Version metadata is supplementary and must not disable analytics.
    }
  }

  Future<void> _initializeMixpanel(Future<void> appVersionReady) async {
    await _completeMixpanelInitialization(
      initializeMixpanelWithRetry<Mixpanel>(
        loadToken: loadMixpanelProjectToken,
        initialize: (projectToken) =>
            Mixpanel.init(projectToken, trackAutomaticEvents: true),
      ),
      appVersionReady: appVersionReady,
    );
  }

  Future<void> _completeMixpanelInitialization(
    Future<Mixpanel?> initialization, {
    Future<void>? appVersionReady,
  }) async {
    final mixpanel = await initialization;
    if (mixpanel == null) {
      _mixpanelInitializationPending = false;
      _pendingMixpanelEvents.clear();
      return;
    }

    await appVersionReady;
    if (_identifiedAsUser && _uid.isNotEmpty) {
      try {
        await mixpanel.identify(_uid);
      } on Object {
        // Event delivery can continue if identity synchronization fails.
      }
    }

    _mixpanel = mixpanel;
    _mixpanelInitializationPending = false;
    final pendingEvents = List<_PendingMixpanelEvent>.of(
      _pendingMixpanelEvents,
    );
    _pendingMixpanelEvents.clear();
    for (final pending in pendingEvents) {
      _sendMixpanelEvent(mixpanel, pending.event, {
        ...pending.properties,
        AnalyticsProperty.appVersion: _appVersion,
      });
    }
  }

  Mixpanel? _mixpanel;
  final AppFirebase? _firebase;
  String _appVersion;
  final bool _isDebugData;
  bool _mixpanelInitializationPending;
  final List<_PendingMixpanelEvent> _pendingMixpanelEvents = [];
  bool _initialIdentityPending;
  final List<_PendingAnalyticsEvent> _pendingIdentityEvents = [];
  final void Function(String event, Map<String, Object?> properties)?
  _eventObserver;
  final void Function(String event, Map<String, Object?> properties)?
  _firebaseEventObserver;

  static const _clickDebounceWindow = Duration(milliseconds: 500);
  final Map<String, DateTime> _lastClickAt = {};

  String _operatingSystem = _defaultOperatingSystem();
  String _uid = '';
  String _subPlan = '';
  bool _identifiedAsUser = false;

  void track(
    String event, {
    Map<String, Object?> properties = const {},
    String? debounceKey,
  }) {
    final mixpanel = _mixpanel;
    final firebase = _firebase;
    final eventObserver = _eventObserver;
    if (mixpanel == null &&
        firebase == null &&
        eventObserver == null &&
        !_mixpanelInitializationPending &&
        _firebaseEventObserver == null) {
      return;
    }
    if (_isDebouncedClick(event, properties, debounceKey)) return;

    if (_initialIdentityPending) {
      _pendingIdentityEvents.add(
        _PendingAnalyticsEvent(
          event,
          Map<String, Object?>.unmodifiable(properties),
        ),
      );
      return;
    }

    _dispatch(event, properties);
  }

  void _dispatch(String event, Map<String, Object?> properties) {
    final mixpanel = _mixpanel;
    final firebase = _firebase;
    final eventObserver = _eventObserver;
    if (mixpanel == null &&
        firebase == null &&
        eventObserver == null &&
        !_mixpanelInitializationPending &&
        _firebaseEventObserver == null) {
      return;
    }

    final payload = <String, dynamic>{
      AnalyticsProperty.operatingSystem: _operatingSystem,
      AnalyticsProperty.appVersion: _appVersion,
      AnalyticsProperty.uid: _uid,
      AnalyticsProperty.checkDebug: _isDebugData,
      AnalyticsProperty.subPlan: _subPlan,
      ...properties,
    };
    eventObserver?.call(event, Map.unmodifiable(payload));
    _firebaseEventObserver?.call(event, Map.unmodifiable(payload));
    if (mixpanel != null) {
      _sendMixpanelEvent(mixpanel, event, payload);
    } else if (_mixpanelInitializationPending) {
      _pendingMixpanelEvents.add(
        _PendingMixpanelEvent(
          event,
          Map<String, dynamic>.unmodifiable(payload),
        ),
      );
    }
    if (firebase != null) {
      try {
        unawaited(firebase.logEvent(event, payload).catchError((Object _) {}));
      } on Object {
        // Analytics must never interrupt the user action being measured.
      }
    }
  }

  void _sendMixpanelEvent(
    Mixpanel mixpanel,
    String event,
    Map<String, dynamic> properties,
  ) {
    try {
      unawaited(
        mixpanel.track(event, properties: properties).catchError((Object _) {}),
      );
    } on Object {
      // Analytics must never interrupt the user action being measured.
    }
  }

  bool _isDebouncedClick(
    String event,
    Map<String, Object?> properties,
    String? debounceKey,
  ) {
    if (!event.endsWith('_click')) return false;
    final sortedKeys = properties.keys.toList()..sort();
    final signature = [
      event,
      if (debounceKey != null) 'debounce-key=$debounceKey',
      for (final key in sortedKeys) '$key=${properties[key]}',
    ].join('|');
    final now = DateTime.now();
    final previous = _lastClickAt[signature];
    _lastClickAt[signature] = now;
    return previous != null && now.difference(previous) < _clickDebounceWindow;
  }

  void updateDeviceType(Size logicalSize, TargetPlatform platform) {
    final isTablet = logicalSize.shortestSide >= 600;
    _operatingSystem = switch (platform) {
      TargetPlatform.iOS => isTablet ? 'ipad' : 'ios',
      TargetPlatform.android => isTablet ? 'tablet' : 'android',
      _ => platform.name,
    };
  }

  void updateIdentity({required String? uid, required bool isUser}) {
    final normalizedUid = uid?.trim() ?? '';
    final wasInitialIdentityPending = _initialIdentityPending;
    if (!wasInitialIdentityPending &&
        _uid == normalizedUid &&
        _identifiedAsUser == isUser) {
      return;
    }

    final mixpanel = _mixpanel;
    if (mixpanel != null) {
      try {
        if (_identifiedAsUser && !isUser) {
          unawaited(mixpanel.reset().catchError((Object _) {}));
        }
        if (isUser && normalizedUid.isNotEmpty) {
          unawaited(mixpanel.identify(normalizedUid).catchError((Object _) {}));
        }
      } on Object {
        // Identity synchronization is retried on the next auth state update.
      }
    }
    final firebase = _firebase;
    if (firebase != null) {
      try {
        unawaited(
          firebase
              .setIdentity(
                isUser && normalizedUid.isNotEmpty ? normalizedUid : null,
              )
              .catchError((Object _) {}),
        );
      } on Object {
        // Identity synchronization is retried on the next auth state update.
      }
    }
    _uid = normalizedUid;
    _identifiedAsUser = isUser;
    _initialIdentityPending = false;

    if (wasInitialIdentityPending) {
      final pendingEvents = List<_PendingAnalyticsEvent>.of(
        _pendingIdentityEvents,
      );
      _pendingIdentityEvents.clear();
      for (final pending in pendingEvents) {
        _dispatch(pending.event, pending.properties);
      }
    }
  }

  void updateSubscriptionPlan(String? sku) {
    _subPlan = sku?.trim() ?? '';
    final firebase = _firebase;
    if (firebase != null) {
      try {
        unawaited(
          firebase.setSubscriptionPlan(_subPlan).catchError((Object _) {}),
        );
      } on Object {
        // Subscription metadata is supplementary analytics context.
      }
    }
  }

  Future<void> logVerifiedApplePurchase({
    required String transactionId,
    required String productId,
    required String planType,
    required double value,
    required String currency,
  }) {
    final firebase = _firebase;
    if (firebase == null) {
      throw StateError('Firebase Analytics is unavailable.');
    }
    return firebase.logPurchase(
      transactionId: transactionId,
      productId: productId,
      planType: planType,
      value: value,
      currency: currency,
    );
  }

  static String _defaultOperatingSystem() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => defaultTargetPlatform.name,
    };
  }
}

class _PendingMixpanelEvent {
  const _PendingMixpanelEvent(this.event, this.properties);

  final String event;
  final Map<String, dynamic> properties;
}

class _PendingAnalyticsEvent {
  const _PendingAnalyticsEvent(this.event, this.properties);

  final String event;
  final Map<String, Object?> properties;
}

class AnalyticsPageView extends ConsumerStatefulWidget {
  const AnalyticsPageView({
    required this.event,
    required this.child,
    this.properties = const {},
    super.key,
  });

  final String event;
  final Map<String, Object?> properties;
  final Widget child;

  @override
  ConsumerState<AnalyticsPageView> createState() => _AnalyticsPageViewState();
}

class _AnalyticsPageViewState extends ConsumerState<AnalyticsPageView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(analyticsProvider)
          .track(widget.event, properties: widget.properties);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
