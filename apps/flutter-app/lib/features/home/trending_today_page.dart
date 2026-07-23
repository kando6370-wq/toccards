import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/search/search_card_tile.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

class TrendingTodayPage extends ConsumerStatefulWidget {
  const TrendingTodayPage({super.key});

  @override
  ConsumerState<TrendingTodayPage> createState() => _TrendingTodayPageState();
}

class _TrendingTodayPageState extends ConsumerState<TrendingTodayPage> {
  var _cards = const <SearchCard>[];
  var _loading = true;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await ref.read(cardDataApiClientProvider).trendingCards();
      if (!mounted) return;
      setState(() {
        _cards = rows.map(searchCardFromDto).toList();
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
      appBar: AppBar(backgroundColor: KandoColors.ink),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          key: const Key('trending-today-refresh'),
          onRefresh: _load,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _cards.isEmpty) {
      return const _FullPageState(child: KandoLoadingBlock());
    }
    if (_failed && _cards.isEmpty) {
      return _FullPageState(child: KandoFailureBlock(onRefresh: _load));
    }
    if (_cards.isEmpty) {
      return const _FullPageState(
        child: KandoEmptyBlock(
          title: 'No trending cards available',
          body: 'Pull down to refresh the latest ranking.',
        ),
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Trending Today',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 32,
                height: 40 / 32,
                fontWeight: FontWeight.w600,
                color: KandoColors.text,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.5,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => SearchCardTile(
                card: _cards[index],
                actionsEnabled: false,
                showActions: false,
              ),
              childCount: _cards.length,
            ),
          ),
        ),
      ],
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
