import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/pagination/pagination.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'search_card_tile.dart';
import 'search_controller.dart';
import 'search_models.dart';
import 'search_repository.dart';

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

  final _cards = <SearchCard>[];
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
      final rows = await ref
          .read(setCatalogApiClientProvider)
          .cardsForSet(widget.setCode, game: widget.game, page: requestedPage);
      final items = rows.map(searchCardFromDto).toList();
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
    final searchState = ref.watch(searchControllerProvider);
    return Scaffold(
      backgroundColor: KandoColors.ink,
      appBar: AppBar(title: Text(widget.setName)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return RefreshIndicator(
              key: const Key('set-detail-pull-to-refresh'),
              onRefresh: () => _load(reset: true),
              child: _body(constraints.maxHeight, searchState),
            );
          },
        ),
      ),
    );
  }

  Widget _body(double viewportHeight, SearchState searchState) {
    if (_loading && _cards.isEmpty) {
      return _fullHeightScrollable(viewportHeight, const KandoLoadingBlock());
    }
    if (_failed && _cards.isEmpty) {
      return _fullHeightScrollable(
        viewportHeight,
        KandoFailureBlock(onRefresh: () => _load(reset: true)),
      );
    }
    if (_cards.isEmpty) {
      return _fullHeightScrollable(
        viewportHeight,
        const KandoEmptyBlock(
          title: 'No cards available',
          body: 'Cards for this set have not been imported yet.',
        ),
      );
    }

    return GridView.builder(
      key: const Key('set-detail-card-grid'),
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.5,
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
        final card = ref
            .read(searchControllerProvider.notifier)
            .resolveCard(_cards[index]);
        return SearchCardTile(
          card: card,
          actionsEnabled:
              !searchState.isLoading &&
              !searchState.isUnavailable &&
              searchState.assetStatus == KandoLoadStatus.content,
        );
      },
    );
  }

  Widget _fullHeightScrollable(double height, Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [SizedBox(height: height, child: child)],
    );
  }
}
