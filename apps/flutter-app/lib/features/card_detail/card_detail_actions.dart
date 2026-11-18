import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/api/api_environment.dart';
import '../../shared/api/app_http_transport.dart';
import '../../shared/card_image/card_image_url.dart';
import '../app_upgrade/app_upgrade_models.dart';
import '../app_upgrade/app_upgrade_repository.dart';
import 'card_share_poster.dart';

final cardDetailActionsProvider = Provider<CardDetailActions>((ref) {
  final dio = ref.watch(appImageDioProvider);
  return PluginCardDetailActions(
    ref.watch(appUpgradeRepositoryProvider),
    loadThumbnail: (imageUrl) => _loadCardShareThumbnail(dio, imageUrl),
  );
});

typedef CardShareLauncher = Future<void> Function(ShareParams params);
typedef CardShareThumbnailLoader = Future<XFile?> Function(String imageUrl);
typedef CardSharePreviewPresenter =
    Future<bool> Function({
      required Uri cardUrl,
      required Future<Uint8List> posterBytes,
    });
typedef CardSharePosterBuilder =
    Future<Uint8List> Function({
      required Uint8List imageBytes,
      required String name,
      required String setName,
      required String marketPrice,
      required Uri cardUrl,
    });

const cardShareFallbackBaseUrl = AppConfig.cardShareBaseUrl;

Future<void> _shareCard(ShareParams params) async {
  await SharePlus.instance.share(params);
}

Future<XFile?> _loadCardShareThumbnail(Dio dio, String imageUrl) async {
  final response = await dio.get<List<int>>(
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
    Rect? sharePositionOrigin,
    CardSharePreviewPresenter? preview,
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
    CardShareThumbnailLoader loadThumbnail = _unavailableThumbnailLoader,
    CardSharePosterBuilder buildPoster = renderCardSharePoster,
    TargetPlatform? platform,
  }) : _share = share,
       _loadThumbnail = loadThumbnail,
       _buildPoster = buildPoster,
       _platform = platform ?? defaultTargetPlatform;

  final AppUpgradeRepository _configRepository;
  final CardShareLauncher _share;
  final CardShareThumbnailLoader _loadThumbnail;
  final CardSharePosterBuilder _buildPoster;
  final TargetPlatform _platform;
  Future<void>? _androidShareInFlight;

  @override
  Future<void> shareCard({
    required String cardRef,
    required String name,
    required String setName,
    required String marketPrice,
    Rect? sharePositionOrigin,
    CardSharePreviewPresenter? preview,
  }) async {
    final inFlight = _androidShareInFlight;
    if (_platform == TargetPlatform.android && inFlight != null) {
      await inFlight;
      return;
    }
    final action = _shareCardOnce(
      cardRef: cardRef,
      name: name,
      setName: setName,
      marketPrice: marketPrice,
      sharePositionOrigin: sharePositionOrigin,
      preview: preview,
    );
    if (_platform == TargetPlatform.android) _androidShareInFlight = action;
    try {
      await action;
    } finally {
      if (identical(_androidShareInFlight, action)) {
        _androidShareInFlight = null;
      }
    }
  }

  Future<void> _shareCardOnce({
    required String cardRef,
    required String name,
    required String setName,
    required String marketPrice,
    Rect? sharePositionOrigin,
    CardSharePreviewPresenter? preview,
  }) async {
    var config = const AppUpgradeConfig();
    try {
      config = await _configRepository.loadConfig();
    } on Object {
      // Sharing keeps its existing public-link fallback when config is offline.
    }
    final baseUrl = AppConfig.isTestEnvironment
        ? Uri.parse(cardShareFallbackBaseUrl)
        : _webUri(config.cardShareBaseUrl) ??
              Uri.parse(cardShareFallbackBaseUrl);
    final cardUrl = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        cardRef,
      ],
    );
    if (_platform == TargetPlatform.iOS) {
      await _share(
        ShareParams(
          uri: cardUrl,
          title: 'Share $name',
          subject: name,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return;
    }

    if (_platform == TargetPlatform.android) {
      final posterBytes = _createPoster(
        cardRef: cardRef,
        name: name,
        setName: setName,
        marketPrice: marketPrice,
        cardUrl: cardUrl,
      );
      // Keep generation errors observed even if the user closes the preview early.
      unawaited(
        posterBytes.then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            debugPrint('Card share poster could not be generated: $error');
          },
        ),
      );
      if (preview != null &&
          !await preview(cardUrl: cardUrl, posterBytes: posterBytes)) {
        return;
      }
      final bytes = await posterBytes;
      await _share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: ['card-ai-card.png'],
          title: 'Share $name',
          subject: name,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return;
    }
    await _share(
      ShareParams(
        text: '$name\n$setName\nMarket price: $marketPrice\n$cardUrl',
        title: 'Share $name',
        subject: name,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  Future<Uint8List> _createPoster({
    required String cardRef,
    required String name,
    required String setName,
    required String marketPrice,
    required Uri cardUrl,
  }) async {
    final image = await _loadThumbnail(
      cardImageUrl(cardRef, CardImageVariant.preview),
    );
    if (image == null) throw StateError('Card image is unavailable.');
    final imageBytes = await image.readAsBytes();
    if (imageBytes.isEmpty) throw StateError('Card image is empty.');
    final bytes = await _buildPoster(
      imageBytes: imageBytes,
      name: name,
      setName: setName,
      marketPrice: marketPrice,
      cardUrl: cardUrl,
    );
    if (bytes.isEmpty) throw StateError('Card share poster is empty.');
    return bytes;
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

Future<XFile?> _unavailableThumbnailLoader(String _) {
  throw StateError('Card share thumbnail loader is unavailable.');
}
