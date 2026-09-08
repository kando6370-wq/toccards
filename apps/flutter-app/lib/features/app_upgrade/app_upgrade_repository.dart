import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/api/api_environment.dart';
import '../../shared/api/api_request_log.dart';
import '../../shared/debug/app_debug_overlay.dart';
import 'app_upgrade_models.dart';

const appUpgradeApiBaseUrl = kandoApiBaseUrl;

final appUpgradeDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: appUpgradeApiBaseUrl,
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 2),
    ),
  );
  dio.interceptors.add(
    ApiRequestTimingInterceptor(ref.read(apiRequestLogProvider.notifier)),
  );
  addAppDebugHttpLogging(dio);
  ref.onDispose(dio.close);
  return dio;
});

final appUpgradeRepositoryProvider = Provider<AppUpgradeRepository>((ref) {
  final platform = defaultTargetPlatform == TargetPlatform.android
      ? 'google'
      : 'ios';
  return HttpAppUpgradeRepository(
    ref.watch(appUpgradeDioProvider),
    platform: platform,
  );
});

final installedVersionReaderProvider = Provider<InstalledVersionReader>((ref) {
  return const PackageInfoInstalledVersionReader();
});

final appStoreLauncherProvider = Provider<AppStoreLauncher>((ref) {
  return const UrlLauncherAppStoreLauncher();
});

final appUpgradeDecisionProvider = FutureProvider<AppUpgradeDecision>((
  ref,
) async {
  final config = await ref.watch(appUpgradeRepositoryProvider).loadConfig();
  final currentVersion = await ref
      .watch(installedVersionReaderProvider)
      .currentVersion();

  return AppUpgradePolicy.evaluate(
    currentVersion: currentVersion,
    config: config,
  );
}, retry: (retryCount, error) => null);

abstract interface class AppUpgradeRepository {
  Future<AppUpgradeConfig> loadConfig();
}

class HttpAppUpgradeRepository implements AppUpgradeRepository {
  const HttpAppUpgradeRepository(this._dio, {this.platform = 'ios'});

  final Dio _dio;
  final String platform;

  @override
  Future<AppUpgradeConfig> loadConfig() async {
    final response = await _dio.get<Map<String, Object?>>(
      '/app-config',
      queryParameters: {'platform': platform},
    );
    final body = response.data;
    final data = body?['data'];
    if (body?['success'] != true ||
        data is! Map<String, Object?> ||
        !data.containsKey('upgrade_prompt')) {
      throw const FormatException('Invalid app version configuration response');
    }
    return AppUpgradeConfig.fromJson(data);
  }
}

abstract interface class InstalledVersionReader {
  Future<String> currentVersion();
}

class PackageInfoInstalledVersionReader implements InstalledVersionReader {
  const PackageInfoInstalledVersionReader();

  @override
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version}+${info.buildNumber}';
  }
}

abstract interface class AppStoreLauncher {
  Future<void> open(String url);
}

class UrlLauncherAppStoreLauncher implements AppStoreLauncher {
  const UrlLauncherAppStoreLauncher();

  @override
  Future<void> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Unable to open the app store');
    }
  }
}
