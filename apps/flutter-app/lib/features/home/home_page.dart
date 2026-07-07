import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'home_controller.dart';
import 'home_models.dart';

const _hiddenAmountText = '••••••';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                currencyCode: state.currencyCode,
                onCurrencyPressed: () => _showCurrencySheet(context, ref),
              ),
              const SizedBox(height: 16),
              _PortfolioCard(
                state: state,
                onFolderPressed: () => _showFolderSheet(context, ref),
                onHidePressed: controller.toggleAmountHidden,
              ),
              const SizedBox(height: 16),
              _ChartRangePicker(
                selected: state.chartRange,
                onSelected: controller.selectChartRange,
              ),
              const SizedBox(height: 16),
              _MostValuableSection(state: state),
              const SizedBox(height: 16),
              _TrendingSection(state: state),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) {
            context.go('/collection');
            return;
          }
          if (index == 3) {
            context.go('/search');
            return;
          }
          if (index == 4) {
            context.go('/profile');
            return;
          }
          if (index != 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This section is coming soon.')),
            );
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            label: 'Collection',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Future<void> _showFolderSheet(BuildContext context, WidgetRef ref) {
    final state = ref.read(homeControllerProvider);

    return showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final folder in state.dashboard.folders)
                ListTile(
                  title: Text(folder.name),
                  trailing: folder.id == state.selectedFolder.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    ref
                        .read(homeControllerProvider.notifier)
                        .selectFolder(folder.id);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCurrencySheet(BuildContext context, WidgetRef ref) {
    final selected = ref.read(homeControllerProvider).currencyCode;

    return showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final currency in const ['USD', 'CNY', 'JPY'])
                ListTile(
                  title: Text(currency),
                  trailing: currency == selected
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    ref
                        .read(homeControllerProvider.notifier)
                        .selectCurrency(currency);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.currencyCode, required this.onCurrencyPressed});

  final String currencyCode;
  final VoidCallback onCurrencyPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Overview',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        OutlinedButton(onPressed: onCurrencyPressed, child: Text(currencyCode)),
      ],
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({
    required this.state,
    required this.onFolderPressed,
    required this.onHidePressed,
  });

  final HomeState state;
  final VoidCallback onFolderPressed;
  final VoidCallback onHidePressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('PORTFOLIO')),
                TextButton(
                  onPressed: onFolderPressed,
                  child: Text(state.selectedFolder.name),
                ),
                IconButton(
                  key: const Key('home-hide-amount'),
                  onPressed: onHidePressed,
                  icon: Icon(
                    state.amountHidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _moneyText(state, state.totalAmountText),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(_moneyText(state, state.changeAmountText)),
                const SizedBox(width: 8),
                Text(state.changePercentText),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              width: double.infinity,
              child: CustomPaint(painter: _ChartPainter(state.chartValues)),
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
    return Wrap(
      spacing: 8,
      children: [
        for (final range in HomeChartRange.values)
          ChoiceChip(
            label: Text(range.label),
            selected: range == selected,
            onSelected: (_) => onSelected(range),
          ),
      ],
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
        Text('Most Valuable', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: card == null
                ? const Text('No cards in this portfolio yet')
                : _CardValueRow(
                    title: card.title,
                    subtitle: card.subtitle,
                    price: _moneyText(state, state.mostValuablePriceText),
                    percent: _percentText(card.change30dPercent),
                  ),
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
        Text('Trending Today', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final card in state.dashboard.trending)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _CardValueRow(
                title: card.title,
                subtitle: card.subtitle,
                price: _moneyText(state, state.formatCardPrice(card.priceUsd)),
                percent: _percentText(card.changeTodayPercent),
              ),
            ),
          ),
      ],
    );
  }
}

class _CardValueRow extends StatelessWidget {
  const _CardValueRow({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.percent,
  });

  final String title;
  final String subtitle;
  final String price;
  final String percent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [Text(price), const SizedBox(height: 4), Text(percent)],
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.teal
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final axisPaint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axisPaint,
    );

    if (values.length < 2) {
      return;
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;
    final path = Path();

    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final normalized = range == 0 ? 0.5 : (values[index] - minValue) / range;
      final y = size.height - normalized * size.height;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

String _moneyText(HomeState state, String value) {
  if (state.amountHidden) {
    return value.contains('in the last 30 days')
        ? '$_hiddenAmountText in the last 30 days'
        : _hiddenAmountText;
  }

  return value.replaceAll('楼', '¥');
}

String _percentText(double value) {
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(1)}%';
}
