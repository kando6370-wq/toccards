import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/search/search_card_tile.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/pagination/pagination.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import '../../shared/analytics/analytics_events.dart';
import '../../shared/analytics/app_analytics.dart';

class TrendingTodayPage extends ConsumerStatefulWidget {
  const TrendingTodayPage({super.key});

  @override
  ConsumerState<TrendingTodayPage> createState() => _TrendingTodayPageState();
}

class _TrendingTodayPageState extends ConsumerState<TrendingTodayPage> {
  var _cards = const <SearchCard>[];
  var _loading = true;
  var _loadingMore = false;
  var _page = 0;
  var _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _page = 0;
      _hasMore = true;
    });
    await _loadPage(1, replace: true);
  }

  Future<void> _refresh() {
    ref.read(analyticsProvider).track(AnalyticsEvent.refreshClick);
    return _load();
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _loadPage(_page + 1, replace: false);
  }

  Future<void> _loadPage(int page, {required bool replace}) async {
    try {
      final api = ref.read(cardDataApiClientProvider);
      final rows = api is PaginatedTrendingCardDataApi
          ? await (api as PaginatedTrendingCardDataApi).trendingCardPage(
              page: page,
            )
          : await api.trendingCards();
      if (!mounted) return;
      setState(() {
        final nextCards = rows
            .where(
              (row) =>
                  row.priceChange1dPercent != null &&
                  row.priceChange1dPercent! > 0,
            )
            .map(searchCardFromDto)
            .toList();
        _cards = replace ? nextCards : [..._cards, ...nextCards];
        _page = page;
        _hasMore = rows.length == kandoPageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KandoColors.ink,
      appBar: AppBar(
        backgroundColor: KandoColors.ink,
        titleSpacing: 0,
        title: const Text(
          'Trending Today',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 24,
            height: 32 / 24,
            fontWeight: FontWeight.w600,
            color: KandoColors.text,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          key: const Key('trending-today-refresh'),
          onRefresh: _refresh,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _cards.isEmpty) {
      return const _FullPageState(child: KandoLoadingBlock());
    }
    if (_cards.isEmpty) {
      return _FullPageState(child: KandoFailureBlock(onRefresh: _refresh));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 350),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent: 378,
                        ),
                    itemCount: _cards.length,
                    itemBuilder: (context, index) => SearchCardTile(
                      card: _cards[index],
                      actionsEnabled: false,
                      showActions: false,
                      showSearchMetadata: true,
                      entrySource: AnalyticsValue.sourceTrendingToday,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _FullPageState extends StatelessWidget {
  const _FullPageState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: constraints.maxHeight, child: child)],
      ),
    );
  }
}
