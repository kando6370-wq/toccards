import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_environment.dart';
import 'analytics_events.dart';

final analyticsProvider = Provider<AppAnalytics>((ref) {
  return AppAnalytics.disabled();
});

class AppAnalytics {
  AppAnalytics._({
    required Mixpanel? mixpanel,
    required String appVersion,
    required bool isDebugData,
    void Function(String event, Map<String, Object?> properties)? eventObserver,
  }) : _mixpanel = mixpanel,
       _appVersion = appVersion,
       _isDebugData = isDebugData,
       _eventObserver = eventObserver;

  factory AppAnalytics.disabled() {
    return AppAnalytics._(mixpanel: null, appVersion: '', isDebugData: true);
  }

  @visibleForTesting
  factory AppAnalytics.recording(
    void Function(String event, Map<String, Object?> properties) onEvent,
  ) {
    return AppAnalytics._(
      mixpanel: null,
      appVersion: '',
      isDebugData: true,
      eventObserver: onEvent,
    );
  }

  static Future<AppAnalytics> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final mixpanel = await Mixpanel.init(
        AppConfig.mixpanelProjectToken,
        trackAutomaticEvents: false,
      );
      return AppAnalytics._(
        mixpanel: mixpanel,
        appVersion: packageInfo.version,
        isDebugData: AppConfig.isDebugData,
      );
    } on Object {
      return AppAnalytics.disabled();
    }
  }

  final Mixpanel? _mixpanel;
  final String _appVersion;
  final bool _isDebugData;
  final void Function(String event, Map<String, Object?> properties)?
  _eventObserver;

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
    final eventObserver = _eventObserver;
    if (mixpanel == null && eventObserver == null) return;
    if (_isDebouncedClick(event, properties, debounceKey)) return;

    final payload = <String, dynamic>{
      AnalyticsProperty.operatingSystem: _operatingSystem,
      AnalyticsProperty.appVersion: _appVersion,
      AnalyticsProperty.uid: _uid,
      AnalyticsProperty.checkDebug: _isDebugData,
      AnalyticsProperty.subPlan: _subPlan,
      ...properties,
    };
    eventObserver?.call(event, Map.unmodifiable(payload));
    if (mixpanel == null) return;
    try {
      unawaited(
        mixpanel.track(event, properties: payload).catchError((Object _) {}),
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
    if (_uid == normalizedUid && _identifiedAsUser == isUser) return;

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
    _uid = normalizedUid;
    _identifiedAsUser = isUser;
  }

  void updateSubscriptionPlan(String? sku) {
    _subPlan = sku?.trim() ?? '';
  }

  static String _defaultOperatingSystem() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => defaultTargetPlatform.name,
    };
  }
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
