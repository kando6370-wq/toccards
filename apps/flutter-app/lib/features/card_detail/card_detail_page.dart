import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'card_detail_controller.dart';

class CardDetailPage extends ConsumerWidget {
  const CardDetailPage({required this.cardId, super.key});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = cardDetailControllerProvider(cardId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => _goBack(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Card Detail'),
      ),
      body: SafeArea(
        child: state.isUnavailable
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: KandoFailureBlock(onRefresh: controller.refresh),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _CardImageStandIn(),
                  const SizedBox(height: 16),
                  _CardHeader(state: state, controller: controller),
                  const SizedBox(height: 16),
                  _BasicInfo(state: state),
                  const SizedBox(height: 16),
                  _PriceOverview(state: state),
                ],
              ),
      ),
    );
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/search');
  }
}

class _CardImageStandIn extends StatelessWidget {
  const _CardImageStandIn();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.style_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context) {
    final detail = state.detail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                detail.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              key: Key('card-detail-wishlist-${detail.id}'),
              onPressed: controller.toggleWishlist,
              icon: Icon(
                detail.isWishlisted ? Icons.favorite : Icons.favorite_border,
              ),
            ),
          ],
        ),
        Text('Market price ${state.marketPriceText}'),
        Text('30D ${state.changeText}'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: detail.isCollected ? null : controller.quickCollect,
          icon: Icon(
            detail.isCollected
                ? Icons.check_circle_outline
                : Icons.add_circle_outline,
          ),
          label: Text(detail.isCollected ? 'Collected' : 'Collect'),
        ),
        const SizedBox(height: 8),
        Text('Qty: ${detail.quantity}'),
      ],
    );
  }
}

class _BasicInfo extends StatelessWidget {
  const _BasicInfo({required this.state});

  final CardDetailState state;

  @override
  Widget build(BuildContext context) {
    final detail = state.detail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Basic information',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        _InfoRow(label: 'Game', value: detail.game),
        _InfoRow(label: 'Set', value: detail.setName),
        _InfoRow(label: 'Identity', value: detail.identityLine),
        _InfoRow(label: 'Finish', value: detail.finish),
        _InfoRow(label: 'Language', value: detail.language),
      ],
    );
  }
}

class _PriceOverview extends StatelessWidget {
  const _PriceOverview({required this.state});

  final CardDetailState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Price overview', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final row in state.marketRows)
          Card(
            child: ListTile(
              title: Text(row.label),
              subtitle: Text('30D ${row.changeText}'),
              trailing: Text(row.priceText),
            ),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
