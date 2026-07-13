import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

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
      body: SafeArea(
        child: state.isUnavailable
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: KandoFailureBlock(onRefresh: controller.refresh),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      currencyCode: state.currencyCode,
                      currencySymbol: state.currency.symbol,
                      onCurrencyPressed: () => _showCurrencySheet(context, ref),
                    ),
                    const SizedBox(height: 20),
                    _PortfolioCard(
                      state: state,
                      onFolderPressed: () => _showFolderSheet(context, ref),
                      onHidePressed: controller.toggleAmountHidden,
                      onRangeSelected: controller.selectChartRange,
                    ),
                    const SizedBox(height: 28),
                    _MostValuableSection(state: state),
                    const SizedBox(height: 28),
                    _TrendingSection(state: state),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _showFolderSheet(BuildContext context, WidgetRef ref) {
    final state = ref.read(homeControllerProvider);

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: KandoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetDragHandle(),
                const SizedBox(height: 16),
                Text(
                  'Select Portfolio',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: KandoColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                for (final folder in state.dashboard.folders) ...[
                  _FolderRow(
                    name: folder.name,
                    isDefault: folder.isDefault,
                    isSelected: folder.id == state.selectedFolder.id,
                    onTap: () {
                      ref
                          .read(homeControllerProvider.notifier)
                          .selectFolder(folder.id);
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                // TODO(figma): add "ADD NEW" folder button plus per-row
                // edit/delete/reorder affordances once folder create/rename/
                // delete/reorder controller actions exist (not in HomeController).
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCurrencySheet(BuildContext context, WidgetRef ref) {
    final selected = ref.read(homeControllerProvider).currencyCode;

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: KandoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                // TODO(figma): add a "Search currency" field once a search/
                // filter state is available (would require new UI state wiring).
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final currency in AppCurrency.values) ...[
                          _CurrencyRow(
                            code: currency.code,
                            label: currency.label,
                            symbol: currency.symbol,
                            isSelected: currency.code == selected,
                            onTap: () {
                              ref
                                  .read(homeControllerProvider.notifier)
                                  .selectCurrency(currency.code);
                              Navigator.of(context).pop();
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: KandoColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: KandoColors.accent),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grid_view_rounded, size: 16, color: KandoColors.accent),
              SizedBox(width: 6),
              Text(
                'Overview',
                style: TextStyle(
                  color: KandoColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onCurrencyPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: KandoColors.elevatedSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: KandoColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currencySymbol,
                  style: const TextStyle(
                    color: KandoColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  currencyCode,
                  style: const TextStyle(
                    color: KandoColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: KandoColors.mutedText,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({
    required this.state,
    required this.onFolderPressed,
    required this.onHidePressed,
    required this.onRangeSelected,
  });

  final HomeState state;
  final VoidCallback onFolderPressed;
  final VoidCallback onHidePressed;
  final ValueChanged<HomeChartRange> onRangeSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KandoColors.elevatedSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KandoColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PORTFOLIO',
            style: TextStyle(
              color: KandoColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  state.totalAmountText,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: KandoColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: const Key('home-hide-amount'),
                onTap: onHidePressed,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    state.amountHidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: KandoColors.mutedText,
                  ),
                ),
              ),
              const Spacer(),
              _FolderPill(
                label: state.selectedFolder.name,
                onPressed: onFolderPressed,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: Text(
                  state.changeAmountText,
                  style: const TextStyle(
                    color: KandoColors.mutedText,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                state.changePercentText,
                style: const TextStyle(
                  color: KandoColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ChartRangePicker(
            selected: state.chartRange,
            onSelected: onRangeSelected,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            width: double.infinity,
            child: CustomPaint(painter: _ChartPainter(state.chartValues)),
          ),
        ],
      ),
    );
  }
}

class _FolderPill extends StatelessWidget {
  const _FolderPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: KandoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KandoColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_horiz_rounded,
              size: 14,
              color: KandoColors.accent,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: KandoColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KandoColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KandoColors.border),
      ),
      child: Row(
        children: [
          for (final range in HomeChartRange.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(range),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: range == selected
                        ? KandoColors.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    range.label.toUpperCase(),
                    style: TextStyle(
                      color: range == selected
                          ? KandoColors.ink
                          : KandoColors.mutedText,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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

class _MostValuableSection extends StatelessWidget {
  const _MostValuableSection({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final card = state.mostValuable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Most Valuable'),
        const SizedBox(height: 12),
        if (card == null)
          const _EmptyCardBlock(message: 'No cards in this portfolio yet')
        else
          // TODO(figma): render a horizontal carousel of top cards once the
          // model exposes more than a single mostValuable highlight.
          _MostValuableTile(
            title: card.title,
            subtitle: card.subtitle,
            price: state.mostValuablePriceText,
            percent: _percentText(
              current: card.priceUsd,
              previous: card.previousPriceUsd,
            ),
            percentColor: _percentColor(
              current: card.priceUsd,
              previous: card.previousPriceUsd,
            ),
          ),
      ],
    );
  }
}

class _TrendingSection extends StatelessWidget {
  const _TrendingSection({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Trending Today'),
        const SizedBox(height: 12),
        for (final card in state.dashboard.trending) ...[
          _TrendingRow(
            title: card.title,
            subtitle: card.subtitle,
            price: state.formatCardPrice(card.priceUsd),
            percent: _percentText(
              current: card.priceUsd,
              previous: card.previousPriceUsd,
            ),
            percentColor: _percentColor(
              current: card.priceUsd,
              previous: card.previousPriceUsd,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: KandoColors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        // TODO(figma): wire "View all" to a list route once navigation target
        // exists; rendered as a visual affordance to match the design.
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'View all',
              style: TextStyle(
                color: KandoColors.accent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward, size: 14, color: KandoColors.accent),
          ],
        ),
      ],
    );
  }
}

class _MostValuableTile extends StatelessWidget {
  const _MostValuableTile({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.percent,
    required this.percentColor,
  });

  final String title;
  final String subtitle;
  final String price;
  final String percent;
  final Color percentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: KandoColors.elevatedSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KandoColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: KandoColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: KandoColors.border),
                ),
                child: const Icon(
                  Icons.style_outlined,
                  color: KandoColors.mutedText,
                  size: 36,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: KandoColors.ink.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    percent,
                    style: TextStyle(
                      color: percentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: KandoColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: KandoColors.mutedText, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            price,
            style: const TextStyle(
              color: KandoColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
  });

  final String title;
  final String subtitle;
  final String price;
  final String percent;
  final Color percentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KandoColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KandoColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: KandoColors.elevatedSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: KandoColors.border),
            ),
            child: const Icon(
              Icons.image_outlined,
              size: 20,
              color: KandoColors.mutedText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: KandoColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KandoColors.mutedText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: const TextStyle(
                  color: KandoColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                percent,
                style: TextStyle(
                  color: percentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
          const Icon(
            Icons.search_rounded,
            size: 40,
            color: KandoColors.accent,
          ),
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

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.isDefault,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final bool isDefault;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: KandoColors.elevatedSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? KandoColors.accent : KandoColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color: isSelected ? KandoColors.accent : KandoColors.mutedText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: KandoColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              isDefault ? Icons.star_rounded : Icons.star_border_rounded,
              size: 20,
              color: isDefault ? KandoColors.accent : KandoColors.mutedText,
            ),
          ],
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
  const _ChartPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = KandoColors.accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final axisPaint = Paint()
      ..color = KandoColors.border
      ..strokeWidth = 1;

    // Dashed baseline for a subtle grid, matching the Figma chart.
    const dashWidth = 6.0;
    const dashGap = 5.0;
    var startX = 0.0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height),
        Offset(math.min(startX + dashWidth, size.width), size.height),
        axisPaint,
      );
      startX += dashWidth + dashGap;
    }

    if (values.length < 2) {
      return;
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;
    final path = Path();
    final points = <Offset>[];

    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final normalized = range == 0 ? 0.5 : (values[index] - minValue) / range;
      // Leave headroom so the peak does not touch the top edge.
      final y = size.height - normalized * (size.height - 8) - 4;
      points.add(Offset(x, y));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Soft gradient area fill under the line.
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
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

String _percentText({required double current, required double previous}) {
  return MarketChange.fromPrices(
    current: current,
    previous: previous,
  ).percentText;
}

Color _percentColor({required double current, required double previous}) {
  final percent = MarketChange.fromPrices(
    current: current,
    previous: previous,
  ).percent;
  if (percent == null || percent == 0) {
    return KandoColors.mutedText;
  }
  return percent > 0 ? KandoColors.accent : _kNegativeColor;
}
