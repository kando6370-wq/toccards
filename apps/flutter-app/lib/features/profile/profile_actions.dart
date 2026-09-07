import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_upgrade/app_upgrade_models.dart';
import '../app_upgrade/app_upgrade_repository.dart';

const profileActionFailureText =
    'Unable to open this page. Please try again later.';
const profileTermsUrl = 'https://tcgcard.fun/terms';
const profilePrivacyUrl = 'https://tcgcard.fun/privacy';
const profileShareFallbackUrl = 'https://tcgcard.fun';

typedef ProfileUrlLauncher = Future<bool> Function(Uri uri);
typedef ProfileShareLauncher = Future<void> Function(ShareParams params);

Future<bool> _launchProfileUrl(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _shareProfile(ShareParams params) async {
  await SharePlus.instance.share(params);
}

final profileActionsProvider = Provider<ProfileActions>((ref) {
  return PluginProfileActions(ref.watch(appUpgradeRepositoryProvider));
});

abstract interface class ProfileActions {
  Future<void> requestScore();
  Future<void> shareWithFriends({Rect? sharePositionOrigin});
  Future<void> openTerms();
  Future<void> openPrivacy();
}

class PluginProfileActions implements ProfileActions {
  PluginProfileActions(
    this._configRepository, {
    ProfileUrlLauncher launchExternal = _launchProfileUrl,
    ProfileShareLauncher share = _shareProfile,
  }) : _launchExternalUrl = launchExternal,
       _share = share;

  final AppUpgradeRepository _configRepository;
  final ProfileUrlLauncher _launchExternalUrl;
  final ProfileShareLauncher _share;
  bool _didAttemptInAppReview = false;
  Future<void>? _scoreActionInFlight;

  @override
  Future<void> requestScore() async {
    final inFlight = _scoreActionInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final action = _requestScoreOnce();
    _scoreActionInFlight = action;
    try {
      await action;
    } finally {
      if (identical(_scoreActionInFlight, action)) {
        _scoreActionInFlight = null;
      }
    }
  }

  Future<void> _requestScoreOnce() async {
    if (!_didAttemptInAppReview) {
      _didAttemptInAppReview = true;
      try {
        final review = InAppReview.instance;
        if (await review.isAvailable()) {
          await review.requestReview();
          return;
        }
      } on Exception {
        // StoreKit does not report silent suppression; explicit failures can
        // still fall back to the configured store review page immediately.
      }
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
  Future<void> shareWithFriends({Rect? sharePositionOrigin}) async {
    final uri = await _configuredUri(
      (config) => config.appStoreUrl,
      fallback: profileShareFallbackUrl,
    );
    await _share(
      ShareParams(
        uri: uri,
        title: 'Share Card AI',
        subject: 'Card AI',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  @override
  Future<void> openTerms() async {
    await _launchExternal(
      await _configuredUri(
        (config) => config.termsUrl,
        fallback: profileTermsUrl,
      ),
    );
  }

  @override
  Future<void> openPrivacy() async {
    await _launchExternal(
      await _configuredUri(
        (config) => config.privacyUrl,
        fallback: profilePrivacyUrl,
      ),
    );
  }

  Future<Uri> _configuredUri(
    String? Function(AppUpgradeConfig config) select, {
    String? fallback,
  }) async {
    final value = select(await _configRepository.loadConfig());
    final uri = _webUri(value) ?? _webUri(fallback);
    if (uri == null) {
      throw StateError('Profile link is not configured.');
    }
    return uri;
  }

  Uri? _webUri(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  Future<void> _launchExternal(Uri uri) async {
    final opened = await _launchExternalUrl(uri);
    if (!opened) {
      throw Exception('Unable to open $uri');
    }
  }
}
