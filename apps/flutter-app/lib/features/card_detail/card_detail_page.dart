import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'card_detail_controller.dart';
import 'card_detail_models.dart';

/// Figma spacing/radius tokens for the card detail module.
const double _kRadiusLg = 16;
const double _kRadiusXl = 24;

/// Section heading style (Figma: Fraunces SemiBold 24/32).
const TextStyle _kSectionTitleStyle = TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.w600,
  height: 1.2,
  color: KandoColors.text,
);

/// Small uppercase label style used on field/table headers.
const TextStyle _kFieldLabelStyle = TextStyle(
  fontSize: 12,
  height: 1.5,
  letterSpacing: 0.4,
  color: KandoColors.mutedText,
);

/// Bordered panel surface shared across the detail sections.
BoxDecoration _kPanel({double radius = _kRadiusLg, bool strong = false}) {
  return BoxDecoration(
    color: strong
        ? KandoColors.elevatedSurface
        : KandoColors.elevatedSurface.withValues(alpha: 0.4),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: KandoColors.border.withValues(alpha: 0.7)),
  );
}

/// Themes the collection-item form fields to match the Figma inputs
/// (filled surface, rounded borders, accent focus) without touching each
/// field's binding.
ThemeData _formFieldTheme(BuildContext context) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return Theme.of(context).copyWith(
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KandoColors.surface,
      isDense: true,
      labelStyle: const TextStyle(color: KandoColors.mutedText),
      floatingLabelStyle: const TextStyle(color: KandoColors.accent),
      enabledBorder: border(KandoColors.border.withValues(alpha: 0.7)),
      focusedBorder: border(KandoColors.accent, 1.5),
    ),
  );
}

class CardDetailPage extends ConsumerWidget {
  const CardDetailPage({required this.cardId, super.key});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = cardDetailControllerProvider(cardId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return Scaffold(
      backgroundColor: KandoColors.ink,
      appBar: AppBar(
        backgroundColor: KandoColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => _goBack(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Card Detail'),
      ),
      body: SafeArea(
        child: state.loadStatus == KandoLoadStatus.loading
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: KandoLoadingBlock(),
              )
            : state.isUnavailable
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: KandoFailureBlock(onRefresh: controller.refresh),
              )
            : ListView(
                key: const Key('card-detail-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  const _CardImageStandIn(),
                  const SizedBox(height: 20),
                  _CardHeader(state: state, controller: controller),
                  if (!state.detail.isCollected &&
                      state.collectionItemDraft != null) ...[
                    const SizedBox(height: 20),
                    _CollectionItemForm(state: state, controller: controller),
                  ],
                  const SizedBox(height: 28),
                  _BasicInfo(state: state),
                  const SizedBox(height: 28),
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
      height: 360,
      width: double.infinity,
      decoration: BoxDecoration(
        color: KandoColors.elevatedSurface,
        borderRadius: BorderRadius.circular(_kRadiusXl),
        border: Border.all(color: KandoColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: KandoColors.accent.withValues(alpha: 0.08),
            blurRadius: 40,
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.style_outlined,
          size: 72,
          color: KandoColors.mutedText,
        ),
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

    final iconButtonStyle = IconButton.styleFrom(
      backgroundColor: KandoColors.elevatedSurface,
      foregroundColor: KandoColors.text,
      side: BorderSide(color: KandoColors.border.withValues(alpha: 0.7)),
      shape: const CircleBorder(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                detail.name,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  color: KandoColors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (detail.isCollected)
              IconButton(
                key: Key('card-detail-share-${detail.id}'),
                onPressed: () {},
                style: iconButtonStyle,
                icon: const Icon(Icons.ios_share_outlined),
              )
            else
              IconButton(
                key: Key('card-detail-wishlist-${detail.id}'),
                onPressed: () async {
                  await controller.toggleWishlist();
                },
                style: iconButtonStyle,
                icon: Icon(
                  detail.isWishlisted ? Icons.favorite : Icons.favorite_border,
                  color: detail.isWishlisted ? KandoColors.accent : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('Market price', style: _kFieldLabelStyle),
            const SizedBox(width: 8),
            Text(
              state.marketPriceText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: KandoColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '30D ${state.changeText}',
              style: const TextStyle(fontSize: 13, color: KandoColors.mutedText),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: KandoColors.accent,
              foregroundColor: KandoColors.ink,
              disabledBackgroundColor: KandoColors.elevatedSurface,
              disabledForegroundColor: KandoColors.mutedText,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
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
        ),
        const SizedBox(height: 10),
        Text(
          'Qty: ${detail.quantity}',
          style: const TextStyle(fontSize: 13, color: KandoColors.mutedText),
        ),
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
        const Text('Basic information', style: _kSectionTitleStyle),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: _kPanel(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: 'Game', value: detail.game),
              _InfoRow(label: 'Set', value: detail.setName),
              _InfoRow(label: 'Identity', value: detail.identityLine),
              _InfoRow(label: 'Finish', value: detail.finish),
              _InfoRow(label: 'Language', value: detail.language),
            ],
          ),
        ),
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
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: KandoColors.elevatedSurface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: KandoColors.border.withValues(alpha: 0.7)),
            ),
            child: TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: KandoColors.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: KandoColors.accent.withValues(alpha: 0.5),
                ),
              ),
              labelColor: KandoColors.accent,
              unselectedLabelColor: KandoColors.mutedText,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 14),
              tabs: const [
                Tab(text: 'Collection Item'),
                Tab(text: 'Price'),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: KandoColors.accent,
                foregroundColor: KandoColors.ink,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: controller.startAddingCollectionItem,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add item'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final item in state.collectionItemRows)
          if (state.editingCollectionItemId == item.id)
            _CollectionItemForm(state: state, controller: controller)
          else
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: _kPanel(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.portfolioName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KandoColors.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Quantity', value: item.quantityText),
                    _InfoRow(label: 'Status', value: item.statusText),
                    _InfoRow(label: 'Language', value: item.languageText),
                    _InfoRow(label: 'Finish', value: item.finishText),
                    _InfoRow(
                      label: 'Purchase price',
                      value: item.purchasePriceText,
                    ),
                    _InfoRow(label: 'Total', value: item.totalText),
                    if (item.notes.isNotEmpty)
                      _InfoRow(label: 'Notes', value: item.notes),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: KandoColors.accent,
                          ),
                          onPressed: () {
                            controller.startEditingCollectionItem(item.id);
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit item'),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: KandoColors.mutedText,
                          ),
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
    final languageValue = cardCollectionLanguages.contains(draft.language)
        ? draft.language
        : cardCollectionLanguages.first;
    final finishValue = cardCollectionFinishes.contains(draft.finish)
        ? draft.finish
        : cardCollectionFinishes.first;
    final gradeValue = cardCollectionGradeValues.contains(draft.grade)
        ? draft.grade
        : cardCollectionGradeValues.first;

    return Container(
      decoration: _kPanel(strong: true),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Theme(
          data: _formFieldTheme(context),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OWNERSHIP SUMMARY',
              style: _kFieldLabelStyle.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
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
                  for (final folder in state.detail.portfolioFolders)
                    DropdownMenuItem(
                      value: folder.name,
                      child: Text(folder.name),
                    ),
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
                initialValue: gradeValue,
                decoration: const InputDecoration(
                  labelText: 'Grade',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final grade in cardCollectionGradeValues)
                    DropdownMenuItem(
                      value: grade,
                      child: Text('${draft.grader} $grade'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.updateCollectionItemDraft(grade: value);
                  }
                },
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('card-detail-item-language'),
              initialValue: languageValue,
              decoration: const InputDecoration(
                labelText: 'Language',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final language in cardCollectionLanguages)
                  DropdownMenuItem(value: language, child: Text(language)),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.updateCollectionItemDraft(language: value);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('card-detail-item-finish'),
              initialValue: finishValue,
              decoration: const InputDecoration(
                labelText: 'Finish',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final finish in cardCollectionFinishes)
                  DropdownMenuItem(value: finish, child: Text(finish)),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.updateCollectionItemDraft(finish: value);
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
            const SizedBox(height: 8),
            _InfoRow(label: 'Total', value: draft.totalText),
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
                  style: TextButton.styleFrom(
                    foregroundColor: KandoColors.mutedText,
                  ),
                  onPressed: controller.cancelCollectionItemEdit,
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('card-detail-item-submit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KandoColors.accent,
                    foregroundColor: KandoColors.ink,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () async {
                    await controller.saveCollectionItemDraft();
                  },
                  icon: Icon(isEditing ? Icons.save_outlined : Icons.add),
                  label: Text(isEditing ? 'Save changes' : 'Add'),
                ),
              ],
            ),
          ],
          ),
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
    final segStyle = SegmentedButton.styleFrom(
      backgroundColor: KandoColors.elevatedSurface.withValues(alpha: 0.4),
      foregroundColor: KandoColors.mutedText,
      selectedBackgroundColor: KandoColors.accent,
      selectedForegroundColor: KandoColors.ink,
      side: BorderSide(color: KandoColors.border.withValues(alpha: 0.7)),
      shape: const StadiumBorder(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Price overview', style: _kSectionTitleStyle),
        const SizedBox(height: 12),
        const _PriceSubLabel('Price type'),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<CardPriceChartMode>(
            showSelectedIcon: false,
            style: segStyle,
            segments: [
              for (final mode in CardPriceChartMode.values)
                ButtonSegment(value: mode, label: Text(mode.label)),
            ],
            selected: {state.selectedPriceChartMode},
            onSelectionChanged: (selection) {
              controller.selectPriceChartMode(selection.first);
            },
          ),
        ),
        const SizedBox(height: 16),
        const _PriceSubLabel('Price range'),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<CardPriceRange>(
            showSelectedIcon: false,
            style: segStyle,
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
        const SizedBox(height: 20),
        const _PriceSubLabel('Price series'),
        const SizedBox(height: 8),
        if (state.hasPriceSeriesRows) ...[
          for (final row in state.priceSeriesRows)
            _PriceRowTile(title: row.dateLabel, trailing: row.priceText),
        ] else
          Text(
            state.priceSeriesFallbackText,
            style: const TextStyle(color: KandoColors.mutedText),
          ),
        const SizedBox(height: 20),
        const Text('Market Prices', style: _kSectionTitleStyle),
        const SizedBox(height: 12),
        for (final row in state.priceTabMarketRows)
          _PriceRowTile(
            title: row.label,
            subtitle: '7D ${row.changeText}',
            trailing: row.priceText,
          ),
        const SizedBox(height: 20),
        const Text('Sold listings', style: _kSectionTitleStyle),
        const SizedBox(height: 12),
        if (state.hasSoldListingRows) ...[
          for (final row in state.soldListingRows)
            _PriceRowTile(
              title: row.title,
              subtitle: '${row.dateText} - ${row.platform}',
              trailing: row.priceText,
            ),
        ] else
          Text(
            state.soldListingsFallbackText,
            style: const TextStyle(color: KandoColors.mutedText),
          ),
      ],
    );
  }
}

class _PriceSubLabel extends StatelessWidget {
  const _PriceSubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: KandoColors.text,
      ),
    );
  }
}

class _PriceRowTile extends StatelessWidget {
  const _PriceRowTile({
    required this.title,
    required this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _kPanel(radius: 12),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, color: KandoColors.text),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12,
                  color: KandoColors.mutedText,
                ),
              ),
        trailing: Text(
          trailing,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: KandoColors.text,
          ),
        ),
      ),
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
            style: TextButton.styleFrom(
              foregroundColor: KandoColors.mutedText,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: KandoColors.accent,
              foregroundColor: KandoColors.ink,
              shape: const StadiumBorder(),
            ),
            onPressed: () async {
              await controller.removeCollectionItem(itemId);
              if (!context.mounted) {
                return;
              }
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: KandoColors.mutedText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: KandoColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
