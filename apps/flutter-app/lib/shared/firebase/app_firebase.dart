import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../api/api_environment.dart';
import 'firebase_analytics_payload.dart';

class AppFirebase {
  AppFirebase._(this._analytics, this._crashlytics);

  final FirebaseAnalytics _analytics;
  final FirebaseCrashlytics _crashlytics;

  static Future<AppFirebase?> initialize() async {
    try {
      await Firebase.initializeApp();
      final analytics = FirebaseAnalytics.instance;
      final crashlytics = FirebaseCrashlytics.instance;
      final firebase = AppFirebase._(analytics, crashlytics);
      await firebase._setEnvironmentContext();
      return firebase;
    } on Object catch (error) {
      debugPrint(
        'Firebase disabled: add a valid GoogleService-Info.plist to the '
        'Runner target. $error',
      );
      return null;
    }
  }

  void installGlobalErrorHandlers() {
    final previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterErrorHandler?.call(details);
      unawaited(_crashlytics.recordFlutterFatalError(details));
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(_crashlytics.recordError(error, stackTrace, fatal: true));
      return true;
    };
  }

  Future<void> logEvent(String event, Map<String, Object?> properties) {
    return _analytics.logEvent(
      name: event,
      parameters: firebaseAnalyticsParameters(properties),
    );
  }

  Future<void> setIdentity(String? uid) async {
    await Future.wait([
      _analytics.setUserId(id: uid),
      _crashlytics.setUserIdentifier(uid ?? ''),
    ]);
  }

  Future<void> setSubscriptionPlan(String subscriptionPlan) {
    return _analytics.setUserProperty(
      name: 'sub_plan',
      value: subscriptionPlan.isEmpty ? null : subscriptionPlan,
    );
  }

  Future<void> _setEnvironmentContext() async {
    await Future.wait([
      _analytics.setUserProperty(
        name: 'app_environment',
        value: AppConfig.environmentName,
      ),
      _crashlytics.setCustomKey('app_environment', AppConfig.environmentName),
    ]);
  }
}
