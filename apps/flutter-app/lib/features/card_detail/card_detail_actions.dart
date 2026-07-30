import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/card_image/card_image_url.dart';
import '../app_upgrade/app_upgrade_repository.dart';

final cardDetailActionsProvider = Provider<CardDetailActions>((ref) {
  return PluginCardDetailActions(ref.watch(appUpgradeRepositoryProvider));
});

typedef CardShareLauncher = Future<void> Function(ShareParams params);
typedef CardShareThumbnailLoader = Future<XFile?> Function(String imageUrl);

Future<void> _shareCard(ShareParams params) async {
  await SharePlus.instance.share(params);
}

Future<XFile?> _loadCardShareThumbnail(String imageUrl) async {
  final response = await Dio().get<List<int>>(
    imageUrl,
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = response.data;
  if (bytes == null || bytes.isEmpty) return null;
  return XFile.fromData(
    Uint8List.fromList(bytes),
    mimeType: 'image/jpeg',
    name: 'kando-card.jpg',
  );
}

abstract interface class CardDetailActions {
  Future<void> shareCard({
    required String cardRef,
    required String name,
    required String setName,
    required String marketPrice,
  });

  Future<void> openSoldListings({
    required String name,
    required String setName,
  });

  Future<void> openMarketplaceListing(String url);
}

class PluginCardDetailActions implements CardDetailActions {
  PluginCardDetailActions(
    this._configRepository, {
    CardShareLauncher share = _shareCard,
    CardShareThumbnailLoader loadThumbnail = _loadCardShareThumbnail,
    TargetPlatform? platform,
  }) : _share = share,
       _loadThumbnail = loadThumbnail,
       _platform = platform ?? defaultTargetPlatform;

  final AppUpgradeRepository _configRepository;
  final CardShareLauncher _share;
  final CardShareThumbnailLoader _loadThumbnail;
  final TargetPlatform _platform;

  @override
  Future<void> shareCard({
    required String cardRef,
    required String name,
    required String setName,
    required String marketPrice,
  }) async {
    final config = await _configRepository.loadConfig();
    final baseUrl = _webUri(config.cardShareBaseUrl);
    if (baseUrl == null) {
      throw StateError('Card share URL is not configured.');
    }
    final cardUrl = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        cardRef,
      ],
    );
    if (_platform == TargetPlatform.iOS) {
      await _share(
        ShareParams(uri: cardUrl, title: 'Share $name', subject: name),
      );
      return;
    }

    XFile? thumbnail;
    if (_platform == TargetPlatform.android) {
      try {
        thumbnail = await _loadThumbnail(
          cardImageUrl(cardRef, CardImageVariant.preview),
        );
      } catch (_) {
        // Sharing the link is still useful if the preview image cannot load.
      }
    }
    await _share(
      ShareParams(
        text: '$name\n$setName\nMarket price: $marketPrice\n$cardUrl',
        title: 'Share $name',
        subject: name,
        previewThumbnail: thumbnail,
      ),
    );
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

  @override
  Future<void> openSoldListings({
    required String name,
    required String setName,
  }) async {
    final uri = Uri.https('www.ebay.com', '/sch/i.html', {
      '_nkw': '$name $setName',
      'LH_Complete': '1',
      'LH_Sold': '1',
    });
    await _openExternal(uri);
  }

  @override
  Future<void> openMarketplaceListing(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw StateError('Marketplace URL is invalid.');
    }
    await _openExternal(uri);
  }

  Future<void> _openExternal(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw StateError('Could not open marketplace.');
    }
  }
}
