import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'card_detail_controller.dart';
import 'card_detail_models.dart';

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
                key: const Key('card-detail-scroll'),
                padding: const EdgeInsets.all(16),
                children: [
                  const _CardImageStandIn(),
                  const SizedBox(height: 16),
                  _CardHeader(state: state, controller: controller),
                  if (!state.detail.isCollected &&
                      state.collectionItemDraft != null) ...[
                    const SizedBox(height: 16),
                    _CollectionItemForm(state: state, controller: controller),
                  ],
                  const SizedBox(height: 16),
                  _BasicInfo(state: state),
                  const SizedBox(height: 16),
                  if (state.detail.isCollected)
                    _OwnedDetailTabs(state: state, controller: controller)
                  else
                    _PriceOverview(state: state, controller: controller),
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
            if (detail.isCollected)
              IconButton(
                key: Key('card-detail-share-${detail.id}'),
                onPressed: () {},
                icon: const Icon(Icons.ios_share_outlined),
              )
            else
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
          onPressed: detail.isCollected
              ? null
              : controller.startAddingCollectionItem,
          icon: Icon(
            detail.isCollected
                ? Icons.check_circle_outline
                : Icons.add_circle_outline,
          ),
          label: Text(detail.isCollected ? 'Collected' : 'Add to Portfolio'),
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

class _OwnedDetailTabs extends StatelessWidget {
  const _OwnedDetailTabs({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Collection Item'),
              Tab(text: 'Price'),
            ],
          ),
          SizedBox(
            height: 360,
            child: TabBarView(
              children: [
                _CollectionItems(state: state, controller: controller),
                SingleChildScrollView(
                  child: _PriceOverview(state: state, controller: controller),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionItems extends StatelessWidget {
  const _CollectionItems({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context) {
    final draft = state.collectionItemDraft;

    return ListView(
      key: const Key('card-detail-collection-items'),
      padding: const EdgeInsets.only(top: 8),
      children: [
        if (draft != null && state.editingCollectionItemId == null) ...[
          _CollectionItemForm(state: state, controller: controller),
          const SizedBox(height: 8),
        ] else if (draft == null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: controller.startAddingCollectionItem,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add item'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final item in state.collectionItemRows)
          if (state.editingCollectionItemId == item.id)
            _CollectionItemForm(state: state, controller: controller)
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.portfolioName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Quantity', value: item.quantityText),
                    _InfoRow(label: 'Status', value: item.statusText),
                    _InfoRow(
                      label: 'Purchase price',
                      value: item.purchasePriceText,
                    ),
                    if (item.notes.isNotEmpty)
                      _InfoRow(label: 'Notes', value: item.notes),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            controller.startEditingCollectionItem(item.id);
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit item'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            _confirmRemoveCollectionItem(
                              context,
                              controller,
                              item.id,
                            );
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove from Portfolio'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _CollectionItemForm extends StatelessWidget {
  const _CollectionItemForm({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context) {
    final draft = state.collectionItemDraft;
    final isEditing = state.editingCollectionItemId != null;
    if (draft == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ownership Summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (isEditing)
              DropdownButtonFormField<String>(
                key: const Key('card-detail-item-portfolio'),
                initialValue: draft.portfolioName,
                decoration: const InputDecoration(
                  labelText: 'Portfolio',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final name in cardCollectionPortfolioNames)
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.updateCollectionItemDraft(portfolioName: value);
                  }
                },
              )
            else
              Text('Adding to ${draft.portfolioName}'),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('card-detail-item-quantity'),
              initialValue: draft.quantityText,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                controller.updateCollectionItemDraft(quantityText: value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('card-detail-item-grader'),
              initialValue: draft.grader,
              decoration: const InputDecoration(
                labelText: 'Grader',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final grader in cardCollectionGraders)
                  DropdownMenuItem(value: grader, child: Text(grader)),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.updateCollectionItemDraft(grader: value);
                }
              },
            ),
            const SizedBox(height: 12),
            if (draft.isRaw)
              DropdownButtonFormField<String>(
                key: const Key('card-detail-item-condition'),
                initialValue: draft.condition,
                decoration: const InputDecoration(
                  labelText: 'Condition',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final condition in cardCollectionConditions)
                    DropdownMenuItem(value: condition, child: Text(condition)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.updateCollectionItemDraft(condition: value);
                  }
                },
              )
            else
              DropdownButtonFormField<String>(
                key: const Key('card-detail-item-grade'),
                initialValue: draft.grade,
                decoration: const InputDecoration(
                  labelText: 'Grade',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final grade in cardCollectionGrades)
                    DropdownMenuItem(value: grade, child: Text(grade)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.updateCollectionItemDraft(grade: value);
                  }
                },
              ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('card-detail-item-purchase-price'),
              initialValue: draft.purchasePriceText,
              decoration: const InputDecoration(
                labelText: 'Purchase price',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                controller.updateCollectionItemDraft(purchasePriceText: value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('card-detail-item-notes'),
              initialValue: draft.notes,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (value) {
                controller.updateCollectionItemDraft(notes: value);
              },
            ),
            if (state.collectionItemFormError != null) ...[
              const SizedBox(height: 8),
              Text(
                state.collectionItemFormError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: controller.cancelCollectionItemEdit,
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('card-detail-item-submit'),
                  onPressed: controller.saveCollectionItemDraft,
                  icon: Icon(isEditing ? Icons.save_outlined : Icons.add),
                  label: Text(isEditing ? 'Save changes' : 'Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceOverview extends StatelessWidget {
  const _PriceOverview({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Price overview', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Price range', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<CardPriceRange>(
            showSelectedIcon: false,
            segments: [
              for (final range in CardPriceRange.values)
                ButtonSegment(value: range, label: Text(range.label)),
            ],
            selected: {state.selectedPriceRange},
            onSelectionChanged: (selection) {
              controller.selectPriceRange(selection.first);
            },
          ),
        ),
        const SizedBox(height: 16),
        Text('Price series', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        if (state.hasPriceSeriesRows) ...[
          for (final row in state.priceSeriesRows)
            Card(
              child: ListTile(
                title: Text(row.dateLabel),
                trailing: Text(row.priceText),
              ),
            ),
        ] else
          Text(state.priceSeriesFallbackText),
        const SizedBox(height: 16),
        Text('Market Prices', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final row in state.priceTabMarketRows)
          Card(
            child: ListTile(
              title: Text(row.label),
              subtitle: Text('7D ${row.changeText}'),
              trailing: Text(row.priceText),
            ),
          ),
        const SizedBox(height: 16),
        Text('Sold listings', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        if (state.hasSoldListingRows) ...[
          for (final row in state.soldListingRows)
            Card(
              child: ListTile(
                title: Text(row.title),
                subtitle: Text('${row.dateText} - ${row.platform}'),
                trailing: Text(row.priceText),
              ),
            ),
        ] else
          Text(state.soldListingsFallbackText),
      ],
    );
  }
}

Future<void> _confirmRemoveCollectionItem(
  BuildContext context,
  CardDetailController controller,
  String itemId,
) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Remove from Portfolio'),
        content: const Text('Remove this Collection Item from your portfolio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              controller.removeCollectionItem(itemId);
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove'),
          ),
        ],
      );
    },
  );
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
