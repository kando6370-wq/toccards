import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import 'card_detail_actions.dart';
import 'card_detail_controller.dart';
import 'card_detail_models.dart';

/// Figma spacing/radius tokens for the card detail module.
const double _kRadiusLg = 16;
const double _kRadiusXl = 24;
const Color _kPositiveColor = Color(0xFF4ADE80);
const Color _kNegativeColor = Color(0xFFFF8989);

/// Section heading style (Figma: Fraunces SemiBold 24/32).
const TextStyle _kSectionTitleStyle = TextStyle(
  fontFamily: 'Fraunces',
  fontSize: 24,
  fontWeight: FontWeight.w600,
  height: 32 / 24,
  color: KandoColors.text,
);

/// Small uppercase label style used on field/table headers.
const TextStyle _kFieldLabelStyle = TextStyle(
  fontSize: 12,
  height: 1.5,
  letterSpacing: 0,
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
            : LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = math.max(
                    20.0,
                    (constraints.maxWidth - 672) / 2,
                  );
                  return ListView(
                    key: const Key('card-detail-scroll'),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      20,
                      horizontalPadding,
                      28,
                    ),
                    children: [
                      _CardHero(
                        state: state,
                        controller: controller,
                        onBack: () => _goBack(context),
                      ),
                      const SizedBox(height: 10),
                      _PrimaryActions(state: state, controller: controller),
                      const SizedBox(height: 28),
                      _BasicInfo(state: state),
                      const SizedBox(height: 28),
                      if (state.detail.isCollected)
                        _OwnedDetailTabs(state: state, controller: controller)
                      else
                        _PriceOverview(state: state, controller: controller),
                      if (state.detail.isWishlisted &&
                          !state.detail.isCollected) ...[
                        const SizedBox(height: 28),
                        _RemoveWishlistButton(controller: controller),
                      ],
                    ],
                  );
                },
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

class _CardImagePlaceholder extends StatelessWidget {
  const _CardImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.style_outlined,
        key: Key('card-detail-image-placeholder'),
        size: 72,
        color: KandoColors.mutedText,
      ),
    );
  }
}

class _CardHero extends ConsumerWidget {
  const _CardHero({
    required this.state,
    required this.controller,
    required this.onBack,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = state.detail;

    final iconButtonStyle = IconButton.styleFrom(
      backgroundColor: KandoColors.surface.withValues(alpha: 0.92),
      foregroundColor: KandoColors.text,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      shape: const CircleBorder(),
      fixedSize: const Size.square(40),
      padding: EdgeInsets.zero,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: AspectRatio(
          key: const Key('card-detail-hero'),
          aspectRatio: 350 / 454,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                center: Alignment(0, -0.25),
                radius: 0.9,
                colors: [
                  Color(0xFF4D4D28),
                  Color(0xFF21220D),
                  Color(0xFF0C0E06),
                ],
              ),
              borderRadius: BorderRadius.circular(_kRadiusXl),
              border: Border.all(
                color: KandoColors.border.withValues(alpha: 0.7),
              ),
              boxShadow: [
                BoxShadow(
                  color: KandoColors.accent.withValues(alpha: 0.08),
                  blurRadius: 40,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kRadiusXl),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(54, 56, 54, 54),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_kRadiusLg),
                      child: detail.imageUrl == null
                          ? const _CardImagePlaceholder()
                          : Image.network(
                              detail.imageUrl!,
                              key: const Key('card-detail-image'),
                              fit: BoxFit.contain,
                              webHtmlElementStrategy:
                                  WebHtmlElementStrategy.fallback,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (context, error, stackTrace) =>
                                  const _CardImagePlaceholder(),
                            ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.5, 1],
                          colors: [Colors.transparent, Color(0xF20D0F08)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 18,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          key: const Key('card-detail-back'),
                          tooltip: 'Back',
                          onPressed: onBack,
                          style: iconButtonStyle,
                          icon: const Icon(Icons.arrow_back, size: 22),
                        ),
                        if (detail.isCollected)
                          IconButton(
                            key: Key('card-detail-share-${detail.id}'),
                            tooltip: 'Share',
                            onPressed: () async {
                              try {
                                await ref
                                    .read(cardDetailActionsProvider)
                                    .shareCard(
                                      name: detail.name,
                                      setName: detail.setName,
                                      marketPrice: state.marketPriceText,
                                    );
                              } catch (_) {
                                if (context.mounted) {
                                  showKandoFailureToast(context);
                                }
                              }
                            },
                            style: iconButtonStyle,
                            icon: const Icon(
                              Icons.ios_share_outlined,
                              size: 20,
                            ),
                          )
                        else
                          IconButton(
                            key: Key('card-detail-wishlist-${detail.id}'),
                            tooltip: detail.isWishlisted
                                ? 'Remove from Wishlist'
                                : 'Add to Wishlist',
                            onPressed: () async {
                              if (detail.isWishlisted) {
                                await _confirmRemoveWishlist(
                                  context,
                                  controller,
                                );
                                return;
                              }
                              try {
                                await controller.toggleWishlist();
                              } catch (_) {
                                if (context.mounted) {
                                  showKandoFailureToast(context);
                                }
                              }
                            },
                            style: iconButtonStyle,
                            icon: Icon(
                              detail.isWishlisted
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 20,
                              color: detail.isWishlisted
                                  ? KandoColors.accent
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            detail.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              height: 32 / 24,
                              color: Color(0xFFE4E3D3),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _HeroChip(label: detail.game, accent: true),
                              _HeroChip(label: detail.setName),
                              _HeroChip(label: detail.identityLine),
                              if (detail.quantity > 0)
                                _HeroChip(label: 'Qty: ${detail.quantity}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: accent
            ? KandoColors.accent.withValues(alpha: 0.1)
            : KandoColors.elevatedSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent
              ? KandoColors.accent.withValues(alpha: 0.2)
              : KandoColors.border,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 16 / 12,
          color: accent ? KandoColors.accent : KandoColors.mutedText,
        ),
      ),
    );
  }
}

class _PrimaryActions extends ConsumerWidget {
  const _PrimaryActions({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = state.detail;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('card-detail-view-sold-listings'),
            style: FilledButton.styleFrom(
              backgroundColor: KandoColors.accent,
              foregroundColor: KandoColors.ink,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 14),
            ),
            onPressed: () async {
              try {
                await ref
                    .read(cardDetailActionsProvider)
                    .openSoldListings(
                      name: detail.name,
                      setName: detail.setName,
                    );
              } catch (_) {
                if (context.mounted) showKandoFailureToast(context);
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('VIEW SOLD LISTINGS'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: detail.isCollected
                  ? KandoColors.mutedText
                  : KandoColors.accent,
              side: BorderSide(
                color: detail.isCollected
                    ? KandoColors.border
                    : KandoColors.accent.withValues(alpha: 0.7),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
            onPressed: detail.isCollected
                ? null
                : () => _openAddCollectionItemSheet(context, controller),
            icon: Icon(
              detail.isCollected
                  ? Icons.check_circle_outline
                  : Icons.add_circle_outline,
            ),
            label: Text(detail.isCollected ? 'Collected' : 'Add to Portfolio'),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Market ${state.marketPriceText}', style: _kFieldLabelStyle),
            const SizedBox(width: 12),
            Text('30D ${state.changeText}', style: _kFieldLabelStyle),
          ],
        ),
      ],
    );
  }
}

class _RemoveWishlistButton extends StatelessWidget {
  const _RemoveWishlistButton({required this.controller});

  final CardDetailController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('card-detail-remove-wishlist'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFACC15),
          side: const BorderSide(color: Color(0xFFFACC15)),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: const StadiumBorder(),
        ),
        onPressed: () => _confirmRemoveWishlist(context, controller),
        icon: const Icon(Icons.bookmark_remove_outlined, size: 20),
        label: const Text('Remove from Wishlist'),
      ),
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

class _OwnedDetailTabs extends StatefulWidget {
  const _OwnedDetailTabs({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  State<_OwnedDetailTabs> createState() => _OwnedDetailTabsState();
}

class _OwnedDetailTabsState extends State<_OwnedDetailTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: KandoColors.elevatedSurface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: KandoColors.border.withValues(alpha: 0.7),
            ),
          ),
          child: TabBar(
            controller: _tabController,
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
        if (_tabController.index == 0)
          _CollectionItems(state: widget.state, controller: widget.controller)
        else
          _PriceOverview(state: widget.state, controller: widget.controller),
      ],
    );
  }
}

class _CollectionItems extends StatelessWidget {
  const _CollectionItems({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('card-detail-collection-items'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.collectionItemDraft == null) ...[
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
              onPressed: () => _openAddCollectionItemSheet(context, controller),
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

Future<void> _openAddCollectionItemSheet(
  BuildContext context,
  CardDetailController controller,
) async {
  controller.startAddingCollectionItem();
  final provider = cardDetailControllerProvider(controller.cardId);
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(provider).collectionItemDraft == null) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _AddCollectionItemSheet(cardId: controller.cardId),
  );

  final current = container.read(provider);
  if (current.collectionItemDraft != null &&
      current.editingCollectionItemId == null) {
    controller.cancelCollectionItemEdit();
  }
}

class _AddCollectionItemSheet extends ConsumerWidget {
  const _AddCollectionItemSheet({required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = cardDetailControllerProvider(cardId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    if (state.isLoading ||
        state.isUnavailable ||
        state.collectionItemDraft == null) {
      return const SizedBox.shrink();
    }
    final draft = state.collectionItemDraft!;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Material(
          key: const Key('card-detail-add-item-sheet'),
          color: const Color(0xFF222222),
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: KandoColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(
                      child: Text(
                        'Collection item',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 30,
                          height: 40 / 30,
                          color: KandoColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Adding to ${draft.portfolioName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 24 / 16,
                          color: KandoColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('card-detail-add-item-scroll'),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Container(
                    decoration: _kPanel(strong: true),
                    child: Column(
                      children: [
                        _AddCollectionItemPreview(detail: state.detail),
                        Divider(
                          height: 1,
                          color: KandoColors.border.withValues(alpha: 0.7),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: _CollectionItemForm(
                            state: state,
                            controller: controller,
                            embedded: true,
                            showHeader: false,
                            showTotal: false,
                            showActions: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                decoration: BoxDecoration(
                  color: KandoColors.ink.withValues(alpha: 0.96),
                  border: Border(
                    top: BorderSide(
                      color: KandoColors.border.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL VALUE', style: _kFieldLabelStyle),
                        Text(
                          state.collectionItemDraftTotalText,
                          style: const TextStyle(
                            color: KandoColors.accent,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 24 / 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('card-detail-item-submit'),
                        style: FilledButton.styleFrom(
                          backgroundColor: KandoColors.accent,
                          foregroundColor: KandoColors.ink,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                        onPressed: () async {
                          final saved = await controller
                              .saveCollectionItemDraft();
                          if (saved && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add this card'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCollectionItemPreview extends StatelessWidget {
  const _AddCollectionItemPreview({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 80,
              height: 112,
              child: detail.imageUrl == null
                  ? const _CardImagePlaceholder()
                  : Image.network(
                      detail.imageUrl!,
                      fit: BoxFit.contain,
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (context, error, stackTrace) =>
                          const _CardImagePlaceholder(),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.game.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KandoColors.accent,
                    fontSize: 13,
                    height: 16 / 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KandoColors.text,
                    fontFamily: 'Fraunces',
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    height: 32 / 24,
                  ),
                ),
                Text(
                  detail.setName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KandoColors.mutedText,
                    fontSize: 16,
                    height: 24 / 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail.identityLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KandoColors.mutedText,
                    fontSize: 12,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionItemForm extends StatelessWidget {
  const _CollectionItemForm({
    required this.state,
    required this.controller,
    this.embedded = false,
    this.showHeader = true,
    this.showTotal = true,
    this.showActions = true,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final bool embedded;
  final bool showHeader;
  final bool showTotal;
  final bool showActions;

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

    final content = Theme(
      data: _formFieldTheme(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Text(
              'OWNERSHIP SUMMARY',
              style: _kFieldLabelStyle.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (isEditing)
            DropdownButtonFormField<String>(
              key: const Key('card-detail-item-portfolio'),
              initialValue: draft.portfolioName,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Portfolio',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final folder in state.detail.portfolioFolders)
                  DropdownMenuItem(
                    value: folder.name,
                    child: Text(folder.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.updateCollectionItemDraft(portfolioName: value);
                }
              },
            )
          else if (showHeader)
            Text('Adding to ${draft.portfolioName}'),
          if (isEditing || showHeader) const SizedBox(height: 12),
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
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Grader',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final grader in cardCollectionGraders)
                DropdownMenuItem(
                  value: grader,
                  child: Text(grader, overflow: TextOverflow.ellipsis),
                ),
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
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Condition',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final condition in cardCollectionConditions)
                  DropdownMenuItem(
                    value: condition,
                    child: Text(condition, overflow: TextOverflow.ellipsis),
                  ),
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
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Grade',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final grade in cardCollectionGradeValues)
                  DropdownMenuItem(
                    value: grade,
                    child: Text(
                      '${draft.grader} $grade',
                      overflow: TextOverflow.ellipsis,
                    ),
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
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Language',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final language in cardCollectionLanguages)
                DropdownMenuItem(
                  value: language,
                  child: Text(language, overflow: TextOverflow.ellipsis),
                ),
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
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Finish',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final finish in cardCollectionFinishes)
                DropdownMenuItem(
                  value: finish,
                  child: Text(finish, overflow: TextOverflow.ellipsis),
                ),
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
          if (showTotal) ...[
            const SizedBox(height: 8),
            _InfoRow(label: 'Total', value: state.collectionItemDraftTotalText),
          ],
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
          if (showActions) ...[
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
        ],
      ),
    );

    if (embedded) {
      return content;
    }

    return Container(
      decoration: _kPanel(strong: true),
      child: Padding(padding: const EdgeInsets.all(16), child: content),
    );
  }
}

class _PriceOverview extends ConsumerWidget {
  const _PriceOverview({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pricePoints = state.selectedPriceSeries;
    final chartValues = pricePoints
        .map((point) => point.priceUsd)
        .whereType<double>()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Price', style: _kSectionTitleStyle),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x1F747B26), Color(0x0A141506)],
            ),
            borderRadius: BorderRadius.circular(_kRadiusLg),
            border: Border.all(
              color: KandoColors.border.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final mode in CardPriceChartMode.values) ...[
                    _PriceModeTab(
                      mode: mode,
                      selected: state.selectedPriceChartMode == mode,
                      onSelected: controller.selectPriceChartMode,
                    ),
                    if (mode != CardPriceChartMode.values.last)
                      const SizedBox(width: 16),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                key: const Key('card-detail-price-chart'),
                height: 192,
                width: double.infinity,
                child: state.priceSeriesStatus == KandoLoadStatus.loading
                    ? const KandoLoadingBlock(
                        key: Key('card-detail-price-chart-loading'),
                      )
                    : state.priceSeriesStatus == KandoLoadStatus.failure
                    ? KandoFailureBlock(
                        key: const Key('card-detail-price-chart-failure'),
                        onRefresh: controller.refreshPriceSeries,
                      )
                    : chartValues.length < 2
                    ? Center(
                        child: Text(
                          state.priceSeriesFallbackText,
                          style: const TextStyle(color: KandoColors.mutedText),
                        ),
                      )
                    : CustomPaint(
                        painter: _PriceChartPainter(values: chartValues),
                      ),
              ),
              if (pricePoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      pricePoints.first.dateLabel,
                      style: _kFieldLabelStyle.copyWith(fontSize: 10),
                    ),
                    Text(
                      state.priceSeriesRows.last.priceText,
                      style: const TextStyle(
                        color: KandoColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      pricePoints.last.dateLabel,
                      style: _kFieldLabelStyle.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final range in CardPriceRange.values)
                    _PriceRangeButton(
                      range: range,
                      selected: state.selectedPriceRange == range,
                      onSelected: controller.selectPriceRange,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Market Prices', style: _kSectionTitleStyle),
        const SizedBox(height: 12),
        if (state.marketPricesStatus == KandoLoadStatus.loading)
          const SizedBox(height: 120, child: KandoLoadingBlock())
        else if (state.marketPricesStatus == KandoLoadStatus.failure)
          KandoFailureBlock(
            key: const Key('card-detail-market-prices-failure'),
            onRefresh: controller.refreshMarketPrices,
          )
        else
          _MarketPricesTable(rows: state.priceTabMarketRows),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Shop', style: _kSectionTitleStyle),
            Text(
              'MARKETPLACE',
              style: _kFieldLabelStyle.copyWith(fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.soldListingsStatus == KandoLoadStatus.loading)
          const SizedBox(height: 120, child: KandoLoadingBlock())
        else if (state.soldListingsStatus == KandoLoadStatus.failure)
          KandoFailureBlock(
            key: const Key('card-detail-shop-failure'),
            onRefresh: controller.refreshSoldListings,
          )
        else if (state.hasSoldListingRows) ...[
          for (final row in state.soldListingRows)
            _ShopTile(
              row: row,
              onTap: row.url == null
                  ? null
                  : () async {
                      try {
                        await ref
                            .read(cardDetailActionsProvider)
                            .openMarketplaceListing(row.url!);
                      } catch (_) {
                        if (context.mounted) showKandoFailureToast(context);
                      }
                    },
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

class _PriceModeTab extends StatelessWidget {
  const _PriceModeTab({
    required this.mode,
    required this.selected,
    required this.onSelected,
  });

  final CardPriceChartMode mode;
  final bool selected;
  final ValueChanged<CardPriceChartMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onSelected(mode),
      child: Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? KandoColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          mode.label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? KandoColors.text : KandoColors.mutedText,
          ),
        ),
      ),
    );
  }
}

class _PriceRangeButton extends StatelessWidget {
  const _PriceRangeButton({
    required this.range,
    required this.selected,
    required this.onSelected,
  });

  final CardPriceRange range;
  final bool selected;
  final ValueChanged<CardPriceRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onSelected(range),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFBAC158) : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: KandoColors.accent.withValues(alpha: 0.2),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Text(
          range.label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            color: selected ? const Color(0xFF191E00) : KandoColors.mutedText,
          ),
        ),
      ),
    );
  }
}

class _MarketPricesTable extends StatelessWidget {
  const _MarketPricesTable({required this.rows});

  final List<CardMarketRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _kPanel(radius: _kRadiusLg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _MarketPricesRow(
            grade: 'GRADE',
            market: 'MARKET',
            change: '7D CHANGE',
            header: true,
          ),
          for (final row in rows)
            _MarketPricesRow(
              grade: row.label,
              market: row.priceText,
              change: row.changeText,
            ),
        ],
      ),
    );
  }
}

class _MarketPricesRow extends StatelessWidget {
  const _MarketPricesRow({
    required this.grade,
    required this.market,
    required this.change,
    this.header = false,
  });

  final String grade;
  final String market;
  final String change;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final changeColor = header
        ? KandoColors.mutedText
        : change.startsWith('-')
        ? _kNegativeColor
        : change.startsWith('+')
        ? _kPositiveColor
        : KandoColors.mutedText;
    final style = TextStyle(
      fontSize: header ? 10 : 13,
      color: header ? KandoColors.mutedText : KandoColors.text,
      fontWeight: header ? FontWeight.w400 : FontWeight.w500,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: header
            ? KandoColors.elevatedSurface.withValues(alpha: 0.45)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: KandoColors.border.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(grade, style: style)),
          Expanded(flex: 3, child: Text(market, style: style)),
          Expanded(
            flex: 3,
            child: Text(
              change,
              textAlign: TextAlign.right,
              style: style.copyWith(color: changeColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.row, this.onTap});

  final CardSoldListingRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _kPanel(radius: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: KandoColors.elevatedSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: KandoColors.mutedText,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.dateText,
                            style: const TextStyle(
                              fontSize: 13,
                              color: KandoColors.mutedText,
                            ),
                          ),
                        ),
                        Text(
                          row.priceText,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFFFFF6AF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 14,
                        color: KandoColors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.platform,
                            style: const TextStyle(
                              fontSize: 11,
                              color: KandoColors.mutedText,
                            ),
                          ),
                        ),
                        if (onTap != null)
                          const Icon(
                            Icons.shopping_cart_outlined,
                            size: 16,
                            color: KandoColors.mutedText,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  const _PriceChartPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var index = 1; index <= 3; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.length < 2) return;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;
    const topInset = 16.0;
    const bottomInset = 12.0;
    final points = <Offset>[];

    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final normalized = range == 0 ? 0.5 : (values[index] - minValue) / range;
      final y =
          size.height -
          bottomInset -
          normalized * (size.height - topInset - bottomInset);
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      path.lineTo(points[index].dx, points[index].dy);
    }

    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KandoColors.accent.withValues(alpha: 0.16),
            KandoColors.accent.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = KandoColors.accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(points.last, 3, Paint()..color = KandoColors.accent);
  }

  @override
  bool shouldRepaint(covariant _PriceChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

Future<void> _confirmRemoveWishlist(
  BuildContext context,
  CardDetailController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Remove from Wishlist'),
        content: const Text('Remove this card from your Wishlist?'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: KandoColors.mutedText),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFACC15),
              foregroundColor: KandoColors.ink,
              shape: const StadiumBorder(),
            ),
            onPressed: () async {
              try {
                await controller.toggleWishlist();
              } catch (_) {
                if (dialogContext.mounted) {
                  showKandoFailureToast(dialogContext);
                }
                return;
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            icon: const Icon(Icons.bookmark_remove_outlined),
            label: const Text('Remove'),
          ),
        ],
      );
    },
  );
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
            style: TextButton.styleFrom(foregroundColor: KandoColors.mutedText),
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
