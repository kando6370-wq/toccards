import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const profileActionFailureText =
    'Unable to open this page. Please try again later.';

const kandoAppStoreUrl = 'https://apps.apple.com/app/kando/id0000000000';
const kandoAppStoreReviewUrl =
    'https://apps.apple.com/app/kando/id0000000000?action=write-review';
const kandoTermsUrl = 'https://kando.app/terms';
const kandoPrivacyUrl = 'https://kando.app/privacy';

final profileActionsProvider = Provider<ProfileActions>((ref) {
  return const PluginProfileActions();
});

abstract interface class ProfileActions {
  Future<void> requestScore();
  Future<void> shareWithFriends();
  Future<void> openTerms();
  Future<void> openPrivacy();
}

class PluginProfileActions implements ProfileActions {
  const PluginProfileActions();

  @override
  Future<void> requestScore() async {
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
      return;
    }

    await _launchExternal(kandoAppStoreReviewUrl);
  }

  @override
  Future<void> shareWithFriends() async {
    await SharePlus.instance.share(
      ShareParams(uri: Uri.parse(kandoAppStoreUrl)),
    );
  }

  @override
  Future<void> openTerms() {
    return _launchExternal(kandoTermsUrl);
  }

  @override
  Future<void> openPrivacy() {
    return _launchExternal(kandoPrivacyUrl);
  }

  Future<void> _launchExternal(String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw Exception('Unable to open $url');
    }
  }
}
