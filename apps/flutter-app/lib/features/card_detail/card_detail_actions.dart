import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/api/api_environment.dart';

final cardDetailActionsProvider = Provider<CardDetailActions>((ref) {
  return const PluginCardDetailActions();
});

typedef CardShareLauncher = Future<void> Function(ShareParams params);

Future<void> _shareCard(ShareParams params) async {
  await SharePlus.instance.share(params);
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
  const PluginCardDetailActions({
    CardShareLauncher share = _shareCard,
    String apiBaseUrl = kandoApiBaseUrl,
  }) : _share = share,
       _apiBaseUrl = apiBaseUrl;

  final CardShareLauncher _share;
  final String _apiBaseUrl;

  @override
  Future<void> shareCard({
    required String cardRef,
    required String name,
    required String setName,
    required String marketPrice,
  }) {
    final cardUrl = Uri.parse(
      '$_apiBaseUrl/cards/${Uri.encodeComponent(cardRef)}',
    );
    return _share(
      ShareParams(
        text: '$name\n$setName\nMarket price: $marketPrice\n$cardUrl',
        title: 'Share $name',
        subject: name,
      ),
    );
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
