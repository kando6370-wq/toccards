import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/api/api_environment.dart';
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
  ref.onDispose(dio.close);
  return dio;
});

final appUpgradeRepositoryProvider = Provider<AppUpgradeRepository>((ref) {
  return HttpAppUpgradeRepository(ref.watch(appUpgradeDioProvider));
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
});

abstract interface class AppUpgradeRepository {
  Future<AppUpgradeConfig> loadConfig();
}

class HttpAppUpgradeRepository implements AppUpgradeRepository {
  const HttpAppUpgradeRepository(this._dio);

  final Dio _dio;

  @override
  Future<AppUpgradeConfig> loadConfig() async {
    try {
      final response = await _dio.get<Map<String, Object?>>('/app-config');
      final body = response.data;
      final data = body?['data'];

      if (data is Map<String, Object?>) {
        return AppUpgradeConfig.fromJson(data);
      }
    } catch (_) {
      return const AppUpgradeConfig();
    }

    return const AppUpgradeConfig();
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
    if (uri == null) return;

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // App Store jump failure is intentionally silent per global rules.
    }
  }
}
