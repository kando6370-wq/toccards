import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_upgrade/app_upgrade_models.dart';
import '../app_upgrade/app_upgrade_repository.dart';

const profileActionFailureText =
    'Unable to open this page. Please try again later.';

final profileActionsProvider = Provider<ProfileActions>((ref) {
  return PluginProfileActions(ref.watch(appUpgradeRepositoryProvider));
});

abstract interface class ProfileActions {
  Future<void> requestScore();
  Future<void> shareWithFriends();
  Future<void> openTerms();
  Future<void> openPrivacy();
}

class PluginProfileActions implements ProfileActions {
  const PluginProfileActions(this._configRepository);

  final AppUpgradeRepository _configRepository;

  @override
  Future<void> requestScore() async {
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
      return;
    }

    final appStoreUri = await _configuredUri((config) => config.appStoreUrl);
    await _launchExternal(
      appStoreUri.replace(
        queryParameters: {
          ...appStoreUri.queryParameters,
          'action': 'write-review',
        },
      ),
    );
  }

  @override
  Future<void> shareWithFriends() async {
    await SharePlus.instance.share(
      ShareParams(uri: await _configuredUri((config) => config.appStoreUrl)),
    );
  }

  @override
  Future<void> openTerms() async {
    await _launchExternal(await _configuredUri((config) => config.termsUrl));
  }

  @override
  Future<void> openPrivacy() async {
    await _launchExternal(await _configuredUri((config) => config.privacyUrl));
  }

  Future<Uri> _configuredUri(
    String? Function(AppUpgradeConfig config) select,
  ) async {
    final value = select(await _configRepository.loadConfig());
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw StateError('Profile link is not configured.');
    }
    return uri;
  }

  Future<void> _launchExternal(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw Exception('Unable to open $uri');
    }
  }
}
