import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/pagination/pagination.dart';
import 'package:kando_app/shared/card_image/card_image_url.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

class SetDetailPage extends ConsumerStatefulWidget {
  const SetDetailPage({
    super.key,
    required this.setCode,
    required this.game,
    required this.setName,
  });

  final String setCode;
  final String game;
  final String setName;

  @override
  ConsumerState<SetDetailPage> createState() => _SetDetailPageState();
}

class _SetDetailPageState extends ConsumerState<SetDetailPage> {
  static const _loadMoreThreshold = 320.0;

  final _cards = <CardDataCardDto>[];
  final _scrollController = ScrollController();
  var _page = 1;
  var _loading = true;
  var _failed = false;
  var _hasMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadNextPageNearBottom);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadNextPageNearBottom)
      ..dispose();
    super.dispose();
  }

  void _loadNextPageNearBottom() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > _loadMoreThreshold ||
        !_hasMore ||
        _loading ||
        _failed) {
      return;
    }
    _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    final requestedPage = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await ref
          .read(setCatalogApiClientProvider)
          .cardsForSet(widget.setCode, game: widget.game, page: requestedPage);
      if (!mounted) return;
      setState(() {
        if (reset) _cards.clear();
        _cards.addAll(items);
        _page = requestedPage;
        _hasMore = items.length == kandoPageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KandoColors.ink,
      appBar: AppBar(title: Text(widget.setName)),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading && _cards.isEmpty) return const KandoLoadingBlock();
    if (_failed && _cards.isEmpty) {
      return KandoFailureBlock(onRefresh: () => _load(reset: true));
    }
    if (_cards.isEmpty) {
      return const KandoEmptyBlock(
        title: 'No cards available',
        body: 'Cards for this set have not been imported yet.',
      );
    }

    return GridView.builder(
      key: const Key('set-detail-card-grid'),
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: _cards.length + (_loading || _failed ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _cards.length) {
          return Center(
            child: _loading
                ? const CircularProgressIndicator()
                : IconButton(
                    key: const Key('set-detail-retry-page'),
                    tooltip: 'Retry loading cards',
                    onPressed: () => _load(reset: false),
                    icon: const Icon(Icons.refresh),
                  ),
          );
        }
        final card = _cards[index];
        return Material(
          color: KandoColors.surface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => context.push('/cards/${card.cardRef}'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox.expand(
                      child: Image.network(
                        cardImageUrl(card.cardRef, CardImageVariant.list),
                        fit: BoxFit.contain,
                        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.style_outlined,
                          color: KandoColors.mutedText,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: KandoColors.text,
                    ),
                  ),
                  Text(
                    card.rarity ?? card.setCode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: KandoColors.mutedText),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
