import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../collection/collection_page.dart';
import '../collection/collection_controller.dart';
import '../collection/collection_models.dart';
import 'home_controller.dart';
import 'home_models.dart';

// Semantic down color for negative price changes. There is no red design token,
// so this maps the Figma negative-change red to the nearest available value.
const Color _kNegativeColor = Color(0xFFE5484D);

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);

    return KandoTabScaffold(
      currentTab: KandoMainTab.home,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-1.05, -1.15),
            radius: 1.15,
            colors: [Color(0xFF3A4019), Color(0xFF1F2110), KandoColors.ink],
            stops: [0, .36, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            key: const Key('home-normal-content'),
            padding: const EdgeInsets.fromLTRB(20, 58, 20, 132),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  currencyCode: state.currencyCode,
                  currencySymbol: state.currency.symbol,
                  onCurrencyPressed: () => _showCurrencySheet(context, ref),
                ),
                const SizedBox(height: 24),
                _PortfolioCard(
                  state: state,
                  onFolderPressed: () => _showFolderSheet(context, ref),
                  onHidePressed: controller.toggleAmountHidden,
                  onRangeSelected: controller.selectChartRange,
                  onRefresh: controller.refresh,
                ),
                const SizedBox(height: 32),
                _MostValuableSection(
                  state: state,
                  onRefresh: controller.refresh,
                  onViewAll: () {
                    ref
                        .read(collectionInitialSortProvider.notifier)
                        .select(CollectionSort.valueDesc);
                    context.go('/collection');
                  },
                ),
                const SizedBox(height: 32),
                _TrendingSection(
                  state: state,
                  onRefresh: controller.refreshTrending,
                  onViewAll: () => context.go('/search'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFolderSheet(BuildContext context, WidgetRef ref) async {
    await showPortfolioFolderSheet(context, ref);
    if (context.mounted) {
      ref.read(homeControllerProvider.notifier).refresh();
    }
  }

  Future<void> _showCurrencySheet(BuildContext context, WidgetRef ref) {
    final selected = ref.read(homeControllerProvider).currencyCode;
    final pageContext = context;
    var query = '';

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KandoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final normalizedQuery = query.trim().toLowerCase();
            final currencies = AppCurrency.values.where((currency) {
              return normalizedQuery.isEmpty ||
                  currency.code.toLowerCase().contains(normalizedQuery) ||
                  currency.label.toLowerCase().contains(normalizedQuery) ||
                  currency.symbol.toLowerCase().contains(normalizedQuery);
            }).toList();
            return FractionallySizedBox(
              heightFactor: 0.88,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    20 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SheetDragHandle(),
                      const SizedBox(height: 16),
                      Text(
                        'Select currency',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: KandoColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('home-currency-search'),
                        onChanged: (value) {
                          setModalState(() => query = value);
                        },
                        style: const TextStyle(
                          color: KandoColors.text,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search currency...',
                          hintStyle: const TextStyle(
                            color: KandoColors.mutedText,
                            fontSize: 15,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: KandoColors.mutedText,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: KandoColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: KandoColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: KandoColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: KandoColors.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final currency in currencies) ...[
                                _CurrencyRow(
                                  code: currency.code,
                                  label: currency.label,
                                  symbol: currency.symbol,
                                  isSelected: currency.code == selected,
                                  onTap: () async {
                                    final success = await ref
                                        .read(homeControllerProvider.notifier)
                                        .selectCurrency(currency.code);
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop();
                                    if (!success) {
                                      showKandoFailureToast(pageContext);
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.currencyCode,
    required this.currencySymbol,
    required this.onCurrencyPressed,
  });

  final String currencyCode;
  final String currencySymbol;
  final VoidCallback onCurrencyPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 115,
            height: 42,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: const Color(0x99F0FE6F)),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: KandoColors.accent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: KandoColors.accent),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Color(0xFF303126),
                      BlendMode.srcIn,
                    ),
                    child: Image(
                      image: AssetImage('assets/home/overview.png'),
                      width: 14,
                      height: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Overview',
                        maxLines: 1,
                        style: TextStyle(
                          color: Color(0xFF303126),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 24 / 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(21),
            onTap: onCurrencyPressed,
            child: SizedBox(
              width: 98,
              height: 42,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: const Color(0x1FFFFFFF)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currencySymbol,
                        style: const TextStyle(
                          color: KandoColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 20 / 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        currencyCode,
                        style: const TextStyle(
                          color: KandoColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 20 / 14,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Image(
                        key: Key('home-currency-chevron'),
                        image: AssetImage('assets/home/currency_chevron.png'),
                        width: 12,
                        height: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({
    required this.state,
    required this.onFolderPressed,
    required this.onHidePressed,
    required this.onRangeSelected,
    required this.onRefresh,
  });

  final HomeState state;
  final VoidCallback onFolderPressed;
  final VoidCallback onHidePressed;
  final ValueChanged<HomeChartRange> onRangeSelected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final chartValues = state.chartValues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'PORTFOLIO',
            style: TextStyle(
              color: Color(0xFF92927D),
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 24 / 16,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        state.totalAmountText,
                        style: const TextStyle(
                          color: KandoColors.accent,
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                          height: 44 / 36,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'Toggle amount visibility',
                    child: GestureDetector(
                      key: const Key('home-hide-amount'),
                      onTap: onHidePressed,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF464835)),
                        ),
                        child: Image.asset(
                          'assets/home/visibility.png',
                          width: 14,
                          height: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _FolderPill(
              label: state.selectedFolder.name,
              onPressed: onFolderPressed,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (state.isUnavailable)
          _FigmaFailurePanel(
            key: const Key('home-failure-chart'),
            height: 306,
            refreshKey: const Key('home-failure-chart-refresh'),
            onRefresh: onRefresh,
          )
        else
          SizedBox(
            height: 203,
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 13, 13, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x1FFFFFFF)),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1F747B26), Color(0x0A141506)],
                ),
              ),
              child: Column(
                children: [
                  _ChartRangePicker(
                    selected: state.chartRange,
                    onSelected: onRangeSelected,
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: CustomPaint(
                      painter: _ChartPainter(
                        values: chartValues,
                        dates: state.chartDates,
                        formattedValues: chartValues
                            .map(state.formatCardPrice)
                            .toList(),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FolderPill extends StatelessWidget {
  const _FolderPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      height: 24,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0x0DF0FE6F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x99F0FE6F), width: .5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/home/switch.png', width: 12, height: 12),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: KandoColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 16 / 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartRangePicker extends StatelessWidget {
  const _ChartRangePicker({required this.selected, required this.onSelected});

  final HomeChartRange selected;
  final ValueChanged<HomeChartRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: KandoColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          children: [
            for (final range in HomeChartRange.values)
              Expanded(
                child: GestureDetector(
                  key: Key('home-chart-range-${range.label}'),
                  onTap: () => onSelected(range),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: range == selected
                          ? const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x99747B26), Color(0x33747B26)],
                            )
                          : null,
                      boxShadow: range == selected
                          ? const [
                              BoxShadow(
                                color: Color(0x0D000000),
                                offset: Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      range.label.toUpperCase(),
                      style: TextStyle(
                        color: range == selected
                            ? KandoColors.accent
                            : const Color(0xFF92927D),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 16 / 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FigmaFailurePanel extends StatelessWidget {
  const _FigmaFailurePanel({
    super.key,
    required this.height,
    required this.refreshKey,
    required this.onRefresh,
  });

  final double height;
  final Key refreshKey;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14FFFFFF)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x1F747B26), Color(0x0A141506)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Image.asset(
                'assets/home/empty_state_illustration.png',
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              noContentAvailableText,
              style: TextStyle(
                color: KandoColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 24 / 16,
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              button: true,
              label: refreshText,
              child: GestureDetector(
                key: refreshKey,
                onTap: onRefresh,
                child: Image.asset(
                  'assets/home/refresh_button.png',
                  width: 123,
                  height: 36,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MostValuableSection extends StatelessWidget {
  const _MostValuableSection({
    required this.state,
    required this.onRefresh,
    required this.onViewAll,
  });

  final HomeState state;
  final VoidCallback onRefresh;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final cards = state.mostValuableCards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Most Valuable',
          isUnavailable: state.isUnavailable,
          viewAllKey: const Key('home-most-valuable-view-all'),
          onViewAll: onViewAll,
        ),
        const SizedBox(height: 16),
        if (state.isUnavailable)
          _FigmaFailurePanel(
            key: const Key('home-failure-most-valuable'),
            height: 256,
            refreshKey: const Key('home-failure-most-valuable-refresh'),
            onRefresh: onRefresh,
          )
        else if (cards.isEmpty)
          const _EmptyCardBlock(message: 'No cards in this portfolio yet')
        else
          SizedBox(
            height: 281,
            child: ListView.separated(
              key: const Key('home-most-valuable-list'),
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final card = cards[index];
                return _MostValuableTile(
                  key: Key(
                    'home-most-valuable-card-${state.selectedFolder.id}-$index',
                  ),
                  card: card,
                  onTap: card.cardRef == null
                      ? null
                      : () => context.push('/cards/${card.cardRef}'),
                  price: state.amountHidden
                      ? hiddenMoneyText
                      : state.formatCardPrice(card.priceUsd),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TrendingSection extends StatelessWidget {
  const _TrendingSection({
    required this.state,
    required this.onRefresh,
    required this.onViewAll,
  });

  final HomeState state;
  final VoidCallback onRefresh;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final trends = state.dashboard.trending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Trending Today',
          isUnavailable:
              state.isUnavailable || state.dashboard.trendingUnavailable,
          viewAllKey: const Key('home-trending-view-all'),
          onViewAll: onViewAll,
        ),
        const SizedBox(height: 16),
        if (!state.isUnavailable && state.dashboard.trendingUnavailable)
          _FigmaFailurePanel(
            key: const Key('home-failure-trending'),
            height: 256,
            refreshKey: const Key('home-failure-trending-refresh'),
            onRefresh: onRefresh,
          )
        else if (trends.isEmpty)
          const _EmptyCardBlock(message: 'No trending cards available')
        else
          for (var index = 0; index < trends.length; index += 1) ...[
            _TrendingRow(
              title: trends[index].title,
              subtitle: trends[index].subtitle,
              price: state.formatCardPrice(trends[index].priceUsd),
              percent: _percentText(
                current: trends[index].priceUsd,
                previous: trends[index].previousPriceUsd,
              ),
              percentColor: _percentColor(
                current: trends[index].priceUsd,
                previous: trends[index].previousPriceUsd,
              ),
              imageAssetPath: trends[index].imageAssetPath,
              imageUrl: trends[index].imageUrl,
              onTap: trends[index].cardRef == null
                  ? null
                  : () => context.push('/cards/${trends[index].cardRef}'),
              showPlaceholder: state.isUnavailable,
              placeholderKey: state.isUnavailable
                  ? Key('home-failure-trend-placeholder-$index')
                  : null,
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.viewAllKey,
    required this.onViewAll,
    this.isUnavailable = false,
  });

  final String title;
  final Key viewAllKey;
  final VoidCallback onViewAll;
  final bool isUnavailable;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                style: const TextStyle(
                  color: KandoColors.text,
                  fontFamily: 'Fraunces',
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  height: 32 / 24,
                  fontVariations: [
                    FontVariation('SOFT', 0),
                    FontVariation('WONK', 1),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (isUnavailable)
          const Text(
            'View',
            style: TextStyle(
              color: Color(0xFF2C3400),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 16 / 13,
            ),
          )
        else
          SizedBox(
            width: 60,
            child: InkWell(
              key: viewAllKey,
              onTap: onViewAll,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View all',
                        style: TextStyle(
                          color: KandoColors.accent,
                          fontWeight: FontWeight.w400,
                          fontSize: 13,
                          height: 16 / 13,
                        ),
                      ),
                      SizedBox(width: 4),
                      Image(
                        key: Key('home-view-all-arrow'),
                        image: AssetImage('assets/home/view_all_arrow.png'),
                        width: 14,
                        height: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MostValuableTile extends StatelessWidget {
  const _MostValuableTile({
    super.key,
    required this.card,
    required this.price,
    required this.onTap,
  });

  final HomeCardHighlight card;
  final String price;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final percent = _percentText(
      current: card.priceUsd,
      previous: card.previousPriceUsd,
    );

    return SizedBox(
      width: 144,
      height: 281,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x1FFFFFFF)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xCC1C1E15), Color(0xE612140D)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                offset: Offset(0, 4),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 155,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: KandoColors.ink,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: _HomeCardImage(
                            imageAssetPath: card.imageAssetPath,
                            imageUrl: card.imageUrl,
                            height: 143,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xB310100B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          percent,
                          style: const TextStyle(
                            color: KandoColors.text,
                            fontFamily: 'Geist',
                            fontSize: 9,
                            height: 12 / 9,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE4E3D3),
                  fontFamily: 'Fraunces',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 20 / 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                card.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KandoColors.mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  height: 18 / 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFF6AF),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 24 / 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendingRow extends StatelessWidget {
  const _TrendingRow({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.percent,
    required this.percentColor,
    required this.imageAssetPath,
    required this.imageUrl,
    required this.onTap,
    required this.showPlaceholder,
    this.placeholderKey,
  });

  final String title;
  final String subtitle;
  final String price;
  final String percent;
  final Color percentColor;
  final String? imageAssetPath;
  final String? imageUrl;
  final VoidCallback? onTap;
  final bool showPlaceholder;
  final Key? placeholderKey;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 17),
        child: Row(
          children: [
            if (showPlaceholder)
              Image.asset(
                'assets/home/trend_placeholder.png',
                key: placeholderKey,
                width: 42,
                height: 58,
                filterQuality: FilterQuality.high,
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 42,
                  height: 58,
                  child: _HomeCardImage(
                    imageAssetPath: imageAssetPath,
                    imageUrl: imageUrl,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE4E3D3),
                      fontFamily: 'Fraunces',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 20 / 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KandoColors.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      height: 18 / 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFF6AF),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 20 / 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  percent,
                  style: TextStyle(
                    color: percentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCardImage extends StatelessWidget {
  const _HomeCardImage({
    required this.imageAssetPath,
    required this.imageUrl,
    this.height,
  });

  final String? imageAssetPath;
  final String? imageUrl;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null) {
      return Image.network(
        url,
        height: height,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) =>
            const ColoredBox(color: KandoColors.surface),
      );
    }
    final asset = imageAssetPath;
    if (asset != null) {
      return Image.asset(
        asset,
        height: height,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
    }
    return const ColoredBox(color: KandoColors.surface);
  }
}

class _EmptyCardBlock extends StatelessWidget {
  const _EmptyCardBlock({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: KandoColors.elevatedSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KandoColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.search_rounded, size: 40, color: KandoColors.accent),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: KandoColors.mutedText),
          ),
        ],
      ),
    );
  }
}

class _SheetDragHandle extends StatelessWidget {
  const _SheetDragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: KandoColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({
    required this.code,
    required this.label,
    required this.symbol,
    required this.isSelected,
    required this.onTap,
  });

  final String code;
  final String label;
  final String symbol;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: KandoColors.elevatedSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? KandoColors.accent : KandoColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? KandoColors.accent : KandoColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: KandoColors.border),
              ),
              child: Text(
                symbol,
                style: TextStyle(
                  color: isSelected ? KandoColors.ink : KandoColors.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      color: KandoColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      color: KandoColors.mutedText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color: isSelected ? KandoColors.accent : KandoColors.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter({
    required this.values,
    required this.dates,
    required this.formattedValues,
  });

  final List<double> values;
  final List<String> dates;
  final List<String> formattedValues;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = KandoColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final gridPaint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;

    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(
        Offset.zero + Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    if (values.length < 2) {
      return;
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;
    final points = <Offset>[];
    const topInset = 18.0;
    const bottomInset = 6.0;
    final availableHeight = size.height - topInset - bottomInset;

    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final normalized = range == 0 ? 0.5 : (values[index] - minValue) / range;
      final y = size.height - bottomInset - normalized * availableHeight;
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final control = Offset((previous.dx + current.dx) / 2, previous.dy);
      path.quadraticBezierTo(control.dx, control.dy, current.dx, current.dy);
    }

    final areaPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          KandoColors.accent.withValues(alpha: 0.2),
          KandoColors.accent.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(areaPath, areaPaint);

    canvas.drawPath(path, linePaint);

    final selectedIndex = (points.length * .68).floor();
    final selected = points[selectedIndex];
    canvas.drawCircle(
      selected,
      6,
      Paint()..color = KandoColors.accent.withValues(alpha: 0.2),
    );
    canvas.drawCircle(selected, 3, Paint()..color = KandoColors.accent);

    final datePainter = TextPainter(
      text: TextSpan(
        text: 'Date: ${_formatChartDate(dates, selectedIndex)}',
        style: const TextStyle(
          color: Color(0xFF92927D),
          fontFamily: 'Geist',
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 16 / 11,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final pricePainter = TextPainter(
      text: TextSpan(
        text: 'Price: ${_chartPrice(formattedValues, selectedIndex)}',
        style: const TextStyle(
          color: KandoColors.accent,
          fontFamily: 'Geist',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 16 / 11,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final tooltipSize = Size(
      math.max(datePainter.width, pricePainter.width) + 16,
      52,
    );
    final tooltipLeft = (selected.dx - 40)
        .clamp(0.0, size.width - tooltipSize.width)
        .toDouble();
    final tooltipTop = (selected.dy + 8)
        .clamp(0.0, size.height - tooltipSize.height)
        .toDouble();
    final tooltipRect = Rect.fromLTWH(
      tooltipLeft,
      tooltipTop,
      tooltipSize.width,
      tooltipSize.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tooltipRect, const Radius.circular(6)),
      Paint()..color = const Color(0xE61A1C14),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tooltipRect, const Radius.circular(6)),
      Paint()
        ..color = const Color(0x99F0FE6F)
        ..style = PaintingStyle.stroke,
    );
    datePainter.paint(canvas, tooltipRect.topLeft + const Offset(8, 8));
    pricePainter.paint(canvas, tooltipRect.topLeft + const Offset(8, 28));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.dates != dates ||
        oldDelegate.formattedValues != formattedValues;
  }
}

String _formatChartDate(List<String> dates, int index) {
  if (index >= dates.length) return '--';
  final value = DateTime.tryParse(dates[index]);
  if (value == null) return dates[index].isEmpty ? '--' : dates[index];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _chartPrice(List<String> formattedValues, int index) {
  return index < formattedValues.length ? formattedValues[index] : '--';
}

String _percentText({required double current, required double? previous}) {
  return MarketChange.fromPrices(
    current: current,
    previous: previous,
  ).percentText;
}

Color _percentColor({required double current, required double? previous}) {
  final percent = MarketChange.fromPrices(
    current: current,
    previous: previous,
  ).percent;
  if (percent == null || percent == 0) {
    return KandoColors.mutedText;
  }
  return percent > 0 ? KandoColors.accent : _kNegativeColor;
}
