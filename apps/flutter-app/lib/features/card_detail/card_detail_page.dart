import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/card_image/kando_card_image.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/pending_collection.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/premium_locked_panel.dart';
import 'package:kando_app/shared/ui/premium_unlocked_toast.dart';
import 'package:kando_app/shared/ui/subscription_restore_result.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../../shared/analytics/analytics_events.dart';
import '../../shared/analytics/app_analytics.dart';
import '../collection/collection_controller.dart';
import '../home/home_controller.dart';
import '../home/home_performance_controller.dart';
import '../search/search_controller.dart';
import '../subscription/subscription_controller.dart';
import '../subscription/subscription_entitlement_cache.dart';
import 'card_detail_actions.dart';
import 'card_detail_controller.dart';
import 'card_detail_models.dart';
import 'card_performance_controller.dart';

/// Figma spacing/radius tokens for the card detail module.
const double _kRadiusLg = 16;
const double _kRadiusXl = 24;
const Color _kCollectionCardStart = Color(0x1F747B26);
const Color _kCollectionCardEnd = Color(0x0A141506);
const Color _kCollectionOutline = Color(0x1A90927C);
const Color _kCollectionSecondaryText = Color(0xFF92927D);
const Color _kRemovePortfolioColor = Color(0xFFFACC15);
const List<String> _kEditGraderOptions = ['Raw', 'PSA', 'BGS', 'CGC', 'SGC'];
const List<String> _kEditConditionOptions = [
  'Near Mint (NM)',
  'Lightly Played (LP)',
  'Moderately Played (MP)',
];

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

class CardDetailPage extends ConsumerStatefulWidget {
  const CardDetailPage({
    required this.cardId,
    this.collectionItemId,
    this.collectionType = AnalyticsValue.collectionNormal,
    this.entrySource = AnalyticsValue.sourceSearch,
    super.key,
  });

  final String cardId;
  final String? collectionItemId;
  final String collectionType;
  final String entrySource;

  @override
  ConsumerState<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends ConsumerState<CardDetailPage> {
  bool _trackedView = false;
  bool _isItemEditSheetOpen = false;

  @override
  void didUpdateWidget(covariant CardDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId) _trackedView = false;
  }

  @override
  Widget build(BuildContext context) {
    final provider = cardDetailControllerProvider(widget.cardId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final premiumState = ref.watch(
      subscriptionControllerProvider.select((value) => value.premiumState),
    );
    final isPro = premiumState == AppPremiumState.premium;
    final selectedFolderId = ref.watch(selectedPortfolioFolderProvider);
    if (premiumState == AppPremiumState.free &&
        state.selectedPriceRange == CardPriceRange.oneYear) {
      Future<void>.microtask(
        () => controller.selectPriceRange(CardPriceRange.threeMonths),
      );
    }
    final currentCollectionItemId = state.loadStatus == KandoLoadStatus.content
        ? _currentCollectionItemId(
            state,
            widget.collectionItemId,
            allowSingleFallback:
                widget.collectionItemId != null &&
                widget.entrySource != AnalyticsValue.sourceHomePerformance,
          )
        : null;
    final hasExplicitCollectionItem =
        widget.collectionItemId != null && currentCollectionItemId != null;
    _trackViewWhenLoaded(state);

    final page = Scaffold(
      backgroundColor: KandoColors.ink,
      bottomNavigationBar:
          !_isItemEditSheetOpen &&
              state.loadStatus == KandoLoadStatus.content &&
              state.collectionItemDraft != null &&
              state.editingCollectionItemId != null
          ? _CollectionEditFooter(state: state, controller: controller)
          : null,
      body: SafeArea(
        child: _CardDetailKeyboardDismissOnPointerDown(
          child: state.loadStatus == KandoLoadStatus.loading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: KandoLoadingBlock(),
                )
              : state.isUnavailable
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: KandoFailureBlock(
                    onRefresh: () {
                      ref
                          .read(analyticsProvider)
                          .track(AnalyticsEvent.refreshClick);
                      controller.refresh();
                    },
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding = math.max(
                      20.0,
                      (constraints.maxWidth - 672) / 2,
                    );
                    return RefreshIndicator(
                      key: const Key('card-detail-pull-to-refresh'),
                      onRefresh: () {
                        ref
                            .read(analyticsProvider)
                            .track(AnalyticsEvent.refreshClick);
                        return controller.refresh();
                      },
                      child: ListView(
                        key: const Key('card-detail-scroll'),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        physics: const AlwaysScrollableScrollPhysics(),
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
                            entrySource: widget.entrySource,
                            isGenericEntry: !hasExplicitCollectionItem,
                            onBack: () => _goBack(context, controller),
                          ),
                          const SizedBox(height: 10),
                          if (state.assetStateStatus == KandoLoadStatus.loading)
                            const SizedBox(
                              key: Key('card-detail-asset-state-loading'),
                              height: 72,
                              child: KandoLoadingBlock(),
                            )
                          else if (state.assetStateStatus ==
                              KandoLoadStatus.failure)
                            KandoFailureBlock(
                              key: const Key('card-detail-asset-state-failure'),
                              onRefresh: controller.refreshAssetState,
                            )
                          else
                            _PrimaryActions(state: state),
                          const SizedBox(height: 28),
                          // _BasicInfo(state: state),
                          // const SizedBox(height: 28),
                          if (hasExplicitCollectionItem)
                            _OwnedDetailTabs(
                              key: ValueKey(currentCollectionItemId),
                              state: state,
                              controller: controller,
                              entrySource: widget.entrySource,
                              isPro: isPro,
                              currentCollectionItemId: currentCollectionItemId,
                            )
                          else
                            _GenericCardDetailSections(
                              state: state,
                              controller: controller,
                              isPro: isPro,
                              selectedFolderId: selectedFolderId,
                              onEditItem: (itemId) =>
                                  _openItemEditor(controller, itemId),
                            ),
                          if (state.assetStateStatus ==
                                  KandoLoadStatus.content &&
                              state.detail.isWishlisted &&
                              !state.detail.isCollected) ...[
                            const SizedBox(height: 28),
                            _RemoveWishlistButton(controller: controller),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          controller.cancelCollectionItemEdit();
        }
      },
      child: page,
    );
  }

  void _trackViewWhenLoaded(CardDetailState state) {
    if (_trackedView || state.loadStatus != KandoLoadStatus.content) return;
    _trackedView = true;
    final properties = <String, Object?>{
      AnalyticsProperty.collectionType: widget.collectionType,
      AnalyticsProperty.ipType: analyticsIpType(state.detail.game),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_trackedView) return;
      ref
          .read(analyticsProvider)
          .track(AnalyticsEvent.cardDetailsView, properties: properties);
    });
  }

  void _goBack(BuildContext context, CardDetailController controller) {
    if (context.canPop()) {
      context.pop();
      return;
    }

    controller.cancelCollectionItemEdit();
    context.go('/search');
  }

  Future<void> _openItemEditor(
    CardDetailController controller,
    String itemId,
  ) async {
    setState(() => _isItemEditSheetOpen = true);
    try {
      await _openEditCollectionItemSheet(
        context,
        controller,
        widget.cardId,
        itemId,
      );
    } finally {
      if (mounted) setState(() => _isItemEditSheetOpen = false);
    }
  }
}

String? _currentCollectionItemId(
  CardDetailState state,
  String? requestedItemId, {
  bool allowSingleFallback = true,
}) {
  final items = state.detail.collectionItems;
  if (requestedItemId != null &&
      items.any((item) => item.id == requestedItemId)) {
    return requestedItemId;
  }
  return allowSingleFallback && items.length == 1 ? items.single.id : null;
}

class _CardDetailKeyboardDismissOnPointerDown extends StatelessWidget {
  const _CardDetailKeyboardDismissOnPointerDown({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final focus = FocusManager.instance.primaryFocus;
        final focusContext = focus?.context;
        if (focus == null || focusContext == null) {
          return;
        }

        final renderObject = focusContext.findRenderObject();
        if (renderObject is RenderBox && renderObject.attached) {
          final localPosition = renderObject.globalToLocal(event.position);
          if (renderObject.paintBounds.contains(localPosition)) {
            return;
          }
        }

        FocusScope.of(context).unfocus();
      },
      child: child,
    );
  }
}

class _CardHero extends ConsumerWidget {
  const _CardHero({
    required this.state,
    required this.controller,
    required this.entrySource,
    required this.isGenericEntry,
    required this.onBack,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final String entrySource;
  final bool isGenericEntry;
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
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: SizedBox(
          key: const Key('card-detail-hero'),
          width: double.infinity,
          height: 454,
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
                      child: KandoCardImage(
                        key: const Key('card-detail-image'),
                        imageUrl: detail.imageUrl,
                        placeholderKey: const Key(
                          'card-detail-image-placeholder',
                        ),
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
                        if (isGenericEntry)
                          IconButton(
                            key: Key(
                              'card-detail-add-to-portfolio-${detail.id}',
                            ),
                            tooltip: 'Add to Portfolio',
                            onPressed: () => _openAddCollectionItemSheet(
                              context,
                              controller,
                              entrySource,
                            ),
                            style: iconButtonStyle,
                            icon: SvgPicture.asset(
                              'assets/search/collection_off.svg',
                              width: 20,
                              height: 20,
                            ),
                          )
                        else
                          Builder(
                            builder: (shareContext) => IconButton(
                              key: Key('card-detail-share-${detail.id}'),
                              tooltip: 'Share',
                              onPressed: () async {
                                ref
                                    .read(analyticsProvider)
                                    .track(AnalyticsEvent.shareCardClick);
                                try {
                                  await ref
                                      .read(cardDetailActionsProvider)
                                      .shareCard(
                                        cardRef: detail.id,
                                        name: detail.name,
                                        setName: detail.setName,
                                        marketPrice: state.marketPriceText,
                                        sharePositionOrigin:
                                            _sharePositionOrigin(shareContext),
                                      );
                                } catch (_) {
                                  if (context.mounted) {
                                    showKandoTopFailureToast(context);
                                  }
                                }
                              },
                              style: iconButtonStyle,
                              icon: SvgPicture.asset(
                                'assets/collection/share.svg',
                                key: const Key('card-detail-share-icon'),
                                width: 24,
                                height: 24,
                              ),
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

Rect? _sharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return null;
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

class _PrimaryActions extends ConsumerWidget {
  const _PrimaryActions({required this.state});

  final CardDetailState state;

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
                if (context.mounted) showKandoTopFailureToast(context);
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
        // const SizedBox(height: 10),
        // Row(
        //   mainAxisAlignment: MainAxisAlignment.center,
        //   children: [
        //     Text('Market ${state.marketPriceText}', style: _kFieldLabelStyle),
        //     const SizedBox(width: 12),
        //     Text('30D ${state.changeText}', style: _kFieldLabelStyle),
        //   ],
        // ),
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
        icon: const _RemoveActionIcon(
          key: Key('card-detail-remove-wishlist-icon'),
        ),
        label: const Text('Remove from Wishlist'),
      ),
    );
  }
}

// ignore: unused_element
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

class _GenericCardDetailSections extends StatelessWidget {
  const _GenericCardDetailSections({
    required this.state,
    required this.controller,
    required this.isPro,
    required this.selectedFolderId,
    required this.onEditItem,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final bool isPro;
  final String? selectedFolderId;
  final ValueChanged<String> onEditItem;

  @override
  Widget build(BuildContext context) {
    final folders = state.detail.portfolioFolders;
    final folderId = folders.any((folder) => folder.id == selectedFolderId)
        ? selectedFolderId
        : folders.where((folder) => folder.isDefault).firstOrNull?.id ??
              folders.firstOrNull?.id;
    final itemIds = {
      for (final item in state.detail.collectionItems)
        if (item.folderId == folderId) item.id,
    };
    final rows = state.collectionItemRows
        .where((row) => itemIds.contains(row.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty) ...[
          _InYourPortfolio(rows: rows, onEditItem: onEditItem),
          const SizedBox(height: 28),
        ],
        _PriceOverview(state: state, controller: controller, isPro: isPro),
      ],
    );
  }
}

class _InYourPortfolio extends StatelessWidget {
  const _InYourPortfolio({required this.rows, required this.onEditItem});

  final List<CardCollectionItemRow> rows;
  final ValueChanged<String> onEditItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('card-detail-in-your-portfolio'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('In Your Portfolio', style: _kSectionTitleStyle),
        const SizedBox(height: 16),
        for (var index = 0; index < rows.length; index++) ...[
          Material(
            key: Key('card-detail-portfolio-item-${rows[index].id}'),
            color: KandoColors.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: KandoColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onEditItem(rows[index].id),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rows[index].statusText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: KandoColors.text,
                                fontSize: 14,
                                height: 16 / 14,
                              ),
                            ),
                            Text(
                              rows[index].finishText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: KandoColors.mutedText,
                                fontSize: 10,
                                height: 16 / 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        rows[index].marketPriceText,
                        style: const TextStyle(
                          color: KandoColors.money,
                          fontSize: 14,
                          height: 24 / 14,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: KandoColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (index != rows.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

Future<void> _openEditCollectionItemSheet(
  BuildContext context,
  CardDetailController controller,
  String cardId,
  String itemId,
) async {
  unawaited(controller.startEditingCollectionItem(itemId));
  if (!context.mounted) return;
  final provider = cardDetailControllerProvider(cardId);
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(provider).collectionItemDraft == null) return;

  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _EditCollectionItemSheet(cardId: cardId),
  );

  final current = container.read(provider);
  if (current.collectionItemDraft != null &&
      current.editingCollectionItemId == itemId) {
    controller.cancelCollectionItemEdit();
  }
}

class _EditCollectionItemSheet extends ConsumerWidget {
  const _EditCollectionItemSheet({required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = cardDetailControllerProvider(cardId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    if (state.collectionItemDraft == null ||
        state.editingCollectionItemId == null) {
      return const SizedBox.shrink();
    }

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        alignment: Alignment.bottomCenter,
        heightFactor: 0.88,
        child: Material(
          key: const Key('card-detail-edit-item-sheet'),
          color: const Color(0xFF222222),
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('card-detail-edit-item-sheet-scroll'),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    children: [
                      _CollectionItemForm(state: state, controller: controller),
                      const SizedBox(height: 12),
                      _RemoveFromPortfolioFooterButton(
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          final removed = await _confirmRemoveCollectionItem(
                            context,
                            controller,
                            state.editingCollectionItemId!,
                          );
                          if (removed == true && navigator.mounted) {
                            navigator.pop(true);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              _EditCollectionItemSheetFooter(
                state: state,
                controller: controller,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditCollectionItemSheetFooter extends StatelessWidget {
  const _EditCollectionItemSheetFooter({
    required this.state,
    required this.controller,
  });

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context) {
    final saving = state.isSavingCollectionItemDraft;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: const BoxDecoration(
          color: KandoColors.ink,
          border: Border(top: BorderSide(color: _kCollectionOutline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          controller.cancelCollectionItemEdit();
                          Navigator.of(context).pop(false);
                        },
                  style: TextButton.styleFrom(
                    backgroundColor: KandoColors.elevatedSurface,
                    foregroundColor: KandoColors.text,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('CANCEL'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 56,
                child: TextButton(
                  key: const Key('card-detail-edit-item-sheet-save'),
                  onPressed: saving
                      ? null
                      : () async {
                          final saved = await controller
                              .saveCollectionItemDraft();
                          if (saved && context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                  style: TextButton.styleFrom(
                    backgroundColor: KandoColors.accent,
                    foregroundColor: KandoColors.primaryOnDefault,
                    shape: const StadiumBorder(),
                  ),
                  child: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('SAVE CHANGES'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnedDetailTabs extends ConsumerStatefulWidget {
  const _OwnedDetailTabs({
    super.key,
    required this.state,
    required this.controller,
    required this.entrySource,
    required this.isPro,
    required this.currentCollectionItemId,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final String entrySource;
  final bool isPro;
  final String? currentCollectionItemId;

  @override
  ConsumerState<_OwnedDetailTabs> createState() => _OwnedDetailTabsState();
}

class _OwnedDetailTabsState extends ConsumerState<_OwnedDetailTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final opensHomePerformance =
        widget.entrySource == AnalyticsValue.sourceHomePerformance &&
        widget.currentCollectionItemId != null;
    _tabController = TabController(
      length: widget.currentCollectionItemId == null ? 2 : 3,
      initialIndex: opensHomePerformance
          ? 1
          : widget.entrySource == AnalyticsValue.sourceEdit
          ? widget.currentCollectionItemId == null
                ? 1
                : 2
          : 0,
      vsync: this,
    )..addListener(_handleTabChange);
    if (opensHomePerformance && widget.isPro) {
      final itemId = widget.currentCollectionItemId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _tabController.index != 1) return;
        unawaited(
          ref
              .read(cardPerformanceControllerProvider(itemId).notifier)
              .load(localPremiumVerified: true),
        );
      });
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _OwnedDetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becamePro = !oldWidget.isPro && widget.isPro;
    if (!widget.isPro ||
        _tabController.index != 1 ||
        widget.currentCollectionItemId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final itemId = widget.currentCollectionItemId;
      if (!mounted ||
          !widget.isPro ||
          _tabController.index != 1 ||
          itemId == null) {
        return;
      }
      final provider = cardPerformanceControllerProvider(itemId);
      final performance = ref.read(provider);
      if (performance.isLoading ||
          (!becamePro && (performance.isFailure || performance.hasLoaded))) {
        return;
      }
      unawaited(ref.read(provider.notifier).load(localPremiumVerified: true));
    });
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging && mounted) {
      setState(() {});
      if (_tabController.index == 1 &&
          widget.isPro &&
          widget.currentCollectionItemId != null) {
        unawaited(
          ref
              .read(
                cardPerformanceControllerProvider(
                  widget.currentCollectionItemId!,
                ).notifier,
              )
              .load(localPremiumVerified: true),
        );
      }
    }
  }

  void _editMissingPurchasePrice() {
    final itemId = widget.currentCollectionItemId;
    if (itemId == null) return;
    unawaited(widget.controller.startEditingCollectionItem(itemId));
    _tabController.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final itemId = widget.currentCollectionItemId;
    final performance = itemId == null
        ? null
        : ref.watch(cardPerformanceControllerProvider(itemId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              key: const Key('card-detail-owned-tabs'),
              width: constraints.maxWidth,
              height: 52,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: KandoColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _kCollectionOutline),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  splashFactory: NoSplash.splashFactory,
                  indicator: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF747B26).withValues(alpha: 0.6),
                        const Color(0xFF747B26).withValues(alpha: 0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        offset: const Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  labelColor: KandoColors.accent,
                  unselectedLabelColor: KandoColors.mutedText,
                  labelStyle: const TextStyle(
                    fontSize: 15,
                    height: 17 / 15,
                    fontWeight: FontWeight.w400,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 15,
                    height: 17 / 15,
                    fontWeight: FontWeight.w400,
                  ),
                  tabs: [
                    const Tab(height: 42, text: 'Collection Item'),
                    if (itemId != null)
                      const Tab(height: 42, text: 'Performance'),
                    const Tab(height: 42, text: 'Price'),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        if (_tabController.index == 0)
          _CollectionItems(
            state: widget.state,
            controller: widget.controller,
            entrySource: widget.entrySource,
          )
        else if (itemId != null && _tabController.index == 1)
          _CardPerformance(
            state: widget.state,
            isPro: widget.isPro,
            performance: performance!,
            onRangeSelected: (range) => ref
                .read(cardPerformanceControllerProvider(itemId).notifier)
                .selectRange(range, localPremiumVerified: true),
            onRefresh: () => ref
                .read(cardPerformanceControllerProvider(itemId).notifier)
                .load(localPremiumVerified: true, force: true),
            onEditPurchasePrice: _editMissingPurchasePrice,
            onUnlock: () => _unlockPerformance(itemId),
          )
        else
          _PriceOverview(
            state: widget.state,
            controller: widget.controller,
            isPro: widget.isPro,
          ),
      ],
    );
  }

  Future<void> _unlockPerformance(String itemId) async {
    final premiumState = await _resolvePremiumForRestrictedAction(ref);
    if (!mounted) return;
    if (premiumState == AppPremiumState.premium) {
      await ref
          .read(cardPerformanceControllerProvider(itemId).notifier)
          .load(localPremiumVerified: true, force: true);
      return;
    }
    if (premiumState == AppPremiumState.unknown) return;
    final result = await context.push<SubscriptionPaywallResult>(
      subscriptionSheetLocation,
    );
    if (!mounted || result == null) return;
    if (result == SubscriptionPaywallResult.premiumRestored) {
      showSubscriptionRestoreResult(
        context,
        type: SubscriptionRestoreResultType.premiumRestored,
      );
    } else {
      showPremiumUnlockedToast(context);
    }
    if (_tabController.index != 1 || widget.currentCollectionItemId != itemId) {
      return;
    }
    await ref
        .read(cardPerformanceControllerProvider(itemId).notifier)
        .load(localPremiumVerified: true, force: true);
  }
}

class _CardPerformance extends StatelessWidget {
  const _CardPerformance({
    required this.state,
    required this.isPro,
    required this.performance,
    required this.onRangeSelected,
    required this.onRefresh,
    required this.onEditPurchasePrice,
    required this.onUnlock,
  });

  final CardDetailState state;
  final bool isPro;
  final CardPerformanceState performance;
  final ValueChanged<PerformanceRange> onRangeSelected;
  final VoidCallback onRefresh;
  final VoidCallback onEditPurchasePrice;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    if (!isPro) {
      return _CardPerformanceLocked(onUnlock: onUnlock);
    }

    if (performance.isLoading && performance.data == null) {
      return const SizedBox(
        key: Key('card-detail-performance-loading'),
        height: 390,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (performance.isFailure && performance.data == null) {
      return KandoFailureBlock(
        key: const Key('card-detail-performance-failure'),
        onRefresh: onRefresh,
      );
    }
    final data = performance.data;
    if (data == null || data.marketPriceStatus == MarketPriceStatus.missing) {
      return const SizedBox(
        key: Key('card-detail-performance-no-data'),
        height: 300,
        child: Center(child: Text('No performance history available.')),
      );
    }
    final missingPrice =
        data.purchasePriceStatus == PurchasePriceStatus.missing;
    final chartSeries = [
      _DetailChartSeries(
        label: missingPrice ? 'Market Value' : 'Profit / Loss',
        points: data.series
            .map(
              (point) => CardPricePoint(
                dateLabel: point.date,
                priceUsd: missingPrice
                    ? point.marketValueUsd
                    : point.profitLossUsd,
              ),
            )
            .toList(),
        color: KandoColors.accent,
      ),
    ];
    final formatter = CurrencyFormatter(currency: state.currency);

    return Column(
      key: const Key('card-detail-performance-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        if (missingPrice)
          _CardPerformanceMetric(
            key: const Key('card-detail-performance-metric-market-value'),
            iconAsset: 'assets/collection/performance_current_value.svg',
            label: 'Market Value',
            value: formatter.formatUsd(data.current.marketValueUsd),
          )
        else
          Row(
            key: const Key('card-detail-performance-metrics-row-1'),
            children: [
              Expanded(
                child: _CardPerformanceMetric(
                  key: const Key(
                    'card-detail-performance-metric-purchase-cost',
                  ),
                  iconAsset: 'assets/collection/performance_purchase_cost.svg',
                  label: 'Purchase Cost',
                  value: formatter.formatUsd(data.current.totalPaidUsd),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CardPerformanceMetric(
                  key: const Key(
                    'card-detail-performance-metric-current-value',
                  ),
                  iconAsset: 'assets/collection/performance_current_value.svg',
                  label: 'Current Value',
                  value: formatter.formatUsd(data.current.marketValueUsd),
                ),
              ),
            ],
          ),
        if (!missingPrice) ...[
          const SizedBox(height: 12),
          Row(
            key: const Key('card-detail-performance-metrics-row-2'),
            children: [
              Expanded(
                child: _CardPerformanceMetric(
                  key: const Key('card-detail-performance-metric-profit-loss'),
                  iconAsset: 'assets/collection/performance_profit_loss.svg',
                  label: 'Profit / Loss',
                  value: data.current.profitLossUsd == null
                      ? '--'
                      : _signedAmount(formatter, data.current.profitLossUsd!),
                  helper: 'Priced cards only',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CardPerformanceMetric(
                  key: const Key('card-detail-performance-metric-return'),
                  iconAsset: 'assets/collection/performance_return.svg',
                  label: 'Return %',
                  value: data.current.returnPercent == null
                      ? '--'
                      : '${data.current.returnPercent!.toStringAsFixed(2)}%',
                  helper: 'Priced cards only',
                ),
              ),
            ],
          ),
        ],
        if (missingPrice) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('card-detail-missing-purchase-price'),
            width: double.infinity,
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: KandoColors.accent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: KandoColors.border.withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: KandoColors.accent,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Add purchase price to calculate your card performance.',
                        style: TextStyle(
                          color: KandoColors.mutedText,
                          fontSize: 14,
                          height: 24 / 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      key: Key('card-detail-edit-missing-purchase-price'),
                      onPressed: onEditPurchasePrice,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        backgroundColor: KandoColors.accent,
                        foregroundColor: KandoColors.primaryOnDefault,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      icon: SizedBox(
                        width: 16,
                        height: 16,
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/collection/performance_edit_collection_item.svg',
                          ),
                        ),
                      ),
                      label: const Text('Edit Collection Item'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),
        Text(
          missingPrice ? 'Price Trend' : 'Performance Chart',
          style: _kSectionTitleStyle,
        ),
        const SizedBox(height: 16),
        Container(
          key: const Key('card-detail-performance-chart-panel'),
          height: 203,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: KandoColors.border.withValues(alpha: 0.55),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF747B26).withValues(alpha: 0.12),
                KandoColors.elevatedSurface.withValues(alpha: 0.28),
              ],
            ),
          ),
          child: Column(
            children: [
              _CardPerformanceRangePicker(
                selected: performance.selectedRange,
                isLoading: performance.isLoading,
                onSelected: onRangeSelected,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: chartSeries.isEmpty
                    ? const Center(
                        child: Text(
                          'No performance history available.',
                          style: _kFieldLabelStyle,
                        ),
                      )
                    : _InteractivePriceChart(
                        key: ValueKey(
                          'card-performance-${performance.selectedRange.apiValue}',
                        ),
                        series: chartSeries,
                        quantities: data.series
                            .map((point) => point.quantity)
                            .toList(),
                        persistentSelection: true,
                        emphasizeSinglePoint: true,
                        semanticKey: const Key('card-detail-performance-chart'),
                        semanticLabel: 'Card performance chart',
                        tooltipRows: [
                          for (final point in data.series)
                            _cardPerformanceTooltipRows(
                              formatter,
                              point,
                              missingPrice: missingPrice,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

List<String> _cardPerformanceTooltipRows(
  CurrencyFormatter formatter,
  PerformancePointDto point, {
  required bool missingPrice,
}) {
  final dailyChange = missingPrice
      ? point.marketValueChangeUsd
      : point.profitLossChangeUsd;
  return [
    'Daily Change: ${dailyChange == null ? '--' : _signedAmount(formatter, dailyChange)}',
    'Market Value: ${formatter.formatUsd(point.marketValueUsd)}',
    if (!missingPrice)
      'Profit / Loss: ${point.profitLossUsd == null ? '--' : _signedAmount(formatter, point.profitLossUsd!)}',
    'Qty: ${point.quantity}${point.quantityChange == null || point.quantityChange == 0 ? '' : ' (${point.quantityChange! > 0 ? '+' : ''}${point.quantityChange})'}',
  ];
}

String _signedAmount(CurrencyFormatter formatter, double value) {
  final formatted = formatter.formatUsd(value);
  return value > 0 ? '+$formatted' : formatted;
}

class _CardPerformanceLocked extends StatelessWidget {
  const _CardPerformanceLocked({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return KandoPremiumLockedPanel(
      key: const Key('card-detail-performance-locked'),
      title: "Track This Card's Performance",
      message: 'See your profit, return, and performance history.',
      buttonLabel: 'Unlock Performance',
      buttonKey: const Key('card-detail-unlock-performance'),
      onPressed: onUnlock,
    );
  }
}

class _CardPerformanceRangePicker extends StatelessWidget {
  const _CardPerformanceRangePicker({
    required this.selected,
    required this.isLoading,
    required this.onSelected,
  });

  final PerformanceRange selected;
  final bool isLoading;
  final ValueChanged<PerformanceRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: KandoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KandoColors.border.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          for (final range in PerformanceRange.values)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: range == selected
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF747B26).withValues(alpha: 0.8),
                              const Color(0xFF747B26).withValues(alpha: 0.45),
                            ],
                          )
                        : null,
                  ),
                  child: InkWell(
                    key: Key('card-detail-performance-range-${range.apiValue}'),
                    borderRadius: BorderRadius.circular(4),
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    splashFactory: NoSplash.splashFactory,
                    onTap: () => onSelected(range),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            range.apiValue,
                            style: TextStyle(
                              color: range == selected
                                  ? KandoColors.accent
                                  : _kCollectionSecondaryText,
                              fontSize: 12,
                              height: 16 / 12,
                            ),
                          ),
                          if (isLoading && range == selected) ...[
                            const SizedBox(width: 4),
                            SizedBox.square(
                              key: Key(
                                'card-detail-performance-range-loading-${range.apiValue}',
                              ),
                              dimension: 10,
                              child: const CircularProgressIndicator(
                                color: KandoColors.accent,
                                strokeWidth: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
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

class _CardPerformanceMetric extends StatelessWidget {
  const _CardPerformanceMetric({
    required this.iconAsset,
    required this.label,
    required this.value,
    this.helper,
    super.key,
  });

  final String iconAsset;
  final String label;
  final String value;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF747B26).withValues(alpha: 0.06),
            const Color(0xFF343434).withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(iconAsset),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KandoColors.mutedText,
                    fontSize: 12,
                    height: 16 / 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: KandoColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 24 / 20,
              ),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 2),
            Text(
              helper!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF999578),
                fontSize: 10,
                height: 14 / 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _CollectionItemMode { empty, summary, edit }

class _CollectionItems extends StatelessWidget {
  const _CollectionItems({
    required this.state,
    required this.controller,
    required this.entrySource,
  });

  static const _modeTransitionDuration = Duration(milliseconds: 380);

  final CardDetailState state;
  final CardDetailController controller;
  final String entrySource;

  @override
  Widget build(BuildContext context) {
    final item = state.collectionItemRows.isEmpty
        ? null
        : state.collectionItemRows.first;
    final showEdit =
        state.collectionItemDraft != null &&
        (item == null || state.editingCollectionItemId == item.id);

    return Column(
      key: const Key('card-detail-collection-items'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.collectionItemDraft == null && item == null) ...[
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
              onPressed: () =>
                  _openAddCollectionItemSheet(context, controller, entrySource),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add item'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _CollectionItemModeTransition(
          duration: _modeTransitionDuration,
          child: showEdit
              ? _CollectionItemForm(
                  key: const ValueKey(_CollectionItemMode.edit),
                  state: state,
                  controller: controller,
                )
              : item != null
              ? Column(
                  key: const ValueKey(_CollectionItemMode.summary),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CollectionItemSummaryCard(
                      item: item,
                      onEdit: () {
                        unawaited(
                          controller.startEditingCollectionItem(item.id),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _RemoveFromPortfolioFooterButton(
                      onPressed: () {
                        _confirmRemoveCollectionItem(
                          context,
                          controller,
                          item.id,
                        );
                      },
                    ),
                  ],
                )
              : const SizedBox.shrink(key: ValueKey(_CollectionItemMode.empty)),
        ),
      ],
    );
  }
}

class _CollectionItemModeTransition extends StatelessWidget {
  const _CollectionItemModeTransition({
    required this.duration,
    required this.child,
  });

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final effectiveDuration = disableAnimations ? Duration.zero : duration;

    return AnimatedSwitcher(
      duration: effectiveDuration,
      reverseDuration: effectiveDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final mode = switch (child.key) {
          ValueKey(value: final _CollectionItemMode value) => value,
          _ => _CollectionItemMode.empty,
        };
        final offset = Tween<Offset>(
          begin: switch (mode) {
            _CollectionItemMode.edit => const Offset(1, 0),
            _CollectionItemMode.summary => const Offset(-1, 0),
            _CollectionItemMode.empty => Offset.zero,
          },
          end: Offset.zero,
        ).animate(animation);

        return ClipRect(
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: offset,
              child: AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) {
                  return Align(
                    alignment: Alignment.topCenter,
                    heightFactor: animation.value,
                    child: child,
                  );
                },
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class _CollectionItemSummaryCard extends StatelessWidget {
  const _CollectionItemSummaryCard({required this.item, required this.onEdit});

  final CardCollectionItemRow item;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final status = _CollectionStatusParts.fromText(item.statusText);

    return Container(
      key: Key('card-detail-collection-item-${item.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kCollectionCardStart, _kCollectionCardEnd],
        ),
        borderRadius: BorderRadius.circular(_kRadiusXl),
        border: Border.all(color: _kCollectionOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'OWNERSHIP\nSUMMARY',
                style: _kCollectionHeadlineStyle,
              ),
              SizedBox(
                height: 44,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KandoColors.accent,
                    foregroundColor: KandoColors.primaryOnDefault,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      height: 16 / 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  onPressed: onEdit,
                  child: const Text('Edit item'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _CollectionStatTile(
                  label: 'QUANTITY',
                  value: _displayQuantity(item.quantityText),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CollectionStatTile(
                  label: 'PORTFOLIO',
                  value: item.portfolioName,
                  labelWeight: FontWeight.w500,
                  labelSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _CollectionDetailRow(label: 'GRADER', value: status.grader),
          const SizedBox(height: 12),
          _CollectionDetailRow(label: status.detailLabel, value: status.detail),
          const SizedBox(height: 12),
          _CollectionDetailRow(label: 'LANGUAGE', value: item.languageText),
          const SizedBox(height: 12),
          _CollectionDetailRow(label: 'FINISH', value: item.finishText),
          const SizedBox(height: 12),
          _CollectionDetailRow(
            label: 'PURCHASE PRICE',
            value: item.purchasePriceText,
            accentValue: true,
          ),
          if (item.notes.isNotEmpty) ...[
            const SizedBox(height: 32),
            const Divider(height: 1, thickness: 1, color: _kCollectionOutline),
            const SizedBox(height: 33),
            const Text('NOTES', style: _kCollectionHeadlineStyle),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(17, 16, 17, 17),
              decoration: BoxDecoration(
                color: KandoColors.elevatedSurface,
                borderRadius: BorderRadius.circular(_kRadiusLg),
                border: Border.all(color: _kCollectionOutline),
              ),
              child: Text(
                item.notes,
                style: const TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: KandoColors.mutedText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoveFromPortfolioFooterButton extends StatelessWidget {
  const _RemoveFromPortfolioFooterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        key: const Key('card-detail-remove-from-portfolio'),
        style: OutlinedButton.styleFrom(
          backgroundColor: _kRemovePortfolioColor.withValues(alpha: 0.12),
          foregroundColor: _kRemovePortfolioColor,
          side: const BorderSide(color: _kRemovePortfolioColor),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 16,
            height: 24 / 16,
            fontWeight: FontWeight.w400,
          ),
        ),
        onPressed: onPressed,
        icon: const _RemoveActionIcon(
          key: Key('card-detail-remove-from-portfolio-icon'),
        ),
        label: const Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Remove from '),
              TextSpan(
                text: 'Portfolio',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoveActionIcon extends StatelessWidget {
  const _RemoveActionIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final dimension = iconTheme.size ?? 20;
    final color = iconTheme.color ?? _kRemovePortfolioColor;

    return SizedBox.square(
      dimension: dimension,
      child: CustomPaint(painter: _RemoveActionIconPainter(color: color)),
    );
  }
}

class _RemoveActionIconPainter extends CustomPainter {
  const _RemoveActionIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 20;
    final scaleY = size.height / 20;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.04167
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.scale(scaleX, scaleY);

    final documentPath = Path()
      ..moveTo(15, 9.5833)
      ..lineTo(15, 5.8333)
      ..lineTo(11.25, 1.6666)
      ..lineTo(2.5, 1.6666)
      ..cubicTo(2.0398, 1.6666, 1.6667, 2.0397, 1.6667, 2.5)
      ..lineTo(1.6667, 17.5)
      ..cubicTo(1.6667, 17.9602, 2.0398, 18.3333, 2.5, 18.3333)
      ..lineTo(7.5, 18.3333);
    canvas.drawPath(documentPath, paint);

    canvas.drawLine(
      const Offset(9.1667, 14.5834),
      const Offset(15, 14.5834),
      paint,
    );

    final foldPath = Path()
      ..moveTo(10.8337, 1.6666)
      ..lineTo(10.8337, 5.8333)
      ..lineTo(15.0004, 5.8333);
    canvas.drawPath(foldPath, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RemoveActionIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

const TextStyle _kCollectionHeadlineStyle = TextStyle(
  fontFamily: 'Fraunces',
  fontSize: 14,
  fontWeight: FontWeight.w600,
  height: 20 / 14,
  color: KandoColors.text,
);

class _CollectionStatusParts {
  const _CollectionStatusParts({
    required this.grader,
    required this.detailLabel,
    required this.detail,
  });

  factory _CollectionStatusParts.fromText(String statusText) {
    final slashParts = statusText.split(' / ');
    if (slashParts.length == 2) {
      return _CollectionStatusParts(
        grader: slashParts.first,
        detailLabel: 'CONDITION',
        detail: slashParts.last,
      );
    }

    final pieces = statusText.trim().split(RegExp(r'\s+'));
    if (pieces.length >= 2) {
      return _CollectionStatusParts(
        grader: pieces.sublist(0, pieces.length - 1).join(' '),
        detailLabel: 'GRADE',
        detail: pieces.last,
      );
    }

    return _CollectionStatusParts(
      grader: statusText,
      detailLabel: 'CONDITION',
      detail: '-',
    );
  }

  final String grader;
  final String detailLabel;
  final String detail;
}

String _displayQuantity(String quantityText) {
  return quantityText.replaceFirst(RegExp(r'^Qty:\s*'), '');
}

class _CollectionStatTile extends StatelessWidget {
  const _CollectionStatTile({
    required this.label,
    required this.value,
    this.labelWeight = FontWeight.w400,
    this.labelSize = 11,
  });

  final String label;
  final String value;
  final FontWeight labelWeight;
  final double labelSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: KandoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KandoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: labelSize,
              height: 18 / labelSize,
              fontWeight: labelWeight,
              color: KandoColors.mutedText,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              height: 24 / 16,
              fontWeight: FontWeight.w400,
              color: KandoColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionDetailRow extends StatelessWidget {
  const _CollectionDetailRow({
    required this.label,
    required this.value,
    this.accentValue = false,
  });

  final String label;
  final String value;
  final bool accentValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: KandoColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KandoColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 18 / 11,
                fontWeight: FontWeight.w400,
                color: KandoColors.mutedText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                height: 24 / 16,
                fontWeight: accentValue ? FontWeight.w600 : FontWeight.w400,
                color: accentValue ? KandoColors.accent : KandoColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openAddCollectionItemSheet(
  BuildContext context,
  CardDetailController controller,
  String entrySource,
) async {
  controller.startAddingCollectionItem();
  final provider = cardDetailControllerProvider(controller.cardId);
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(provider).collectionItemDraft == null) {
    return;
  }

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _AddCollectionItemSheet(
      cardId: controller.cardId,
      entrySource: entrySource,
    ),
  );

  if (saved == true && context.mounted) {
    showKandoCenteredSuccessToast(
      context,
      message: portfolioCardAddedToastText,
    );
  }

  final current = container.read(provider);
  if (current.collectionItemDraft != null &&
      current.editingCollectionItemId == null) {
    controller.cancelCollectionItemEdit();
  }
}

class QuickCollectionReviewPage extends ConsumerStatefulWidget {
  const QuickCollectionReviewPage({super.key});

  @override
  ConsumerState<QuickCollectionReviewPage> createState() =>
      _QuickCollectionReviewPageState();
}

class _QuickCollectionReviewPageState
    extends ConsumerState<QuickCollectionReviewPage> {
  int _selectedIndex = 0;
  String? _initializingItemId;
  String? _activeItemId;
  bool _isSavingAll = false;
  CardDetailState? _savingDisplayState;
  int _savingCompletedCount = 0;
  int _savingTotalCount = 0;
  final Set<String> _prefetchedCardIds = {};

  @override
  Widget build(BuildContext context) {
    final pendingItems = ref.watch(pendingCollectionProvider);
    if (pendingItems.isEmpty) {
      if (_isSavingAll) return const _QuickCollectionLoading();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/search');
        }
      });
      return const SizedBox.shrink();
    }

    final selectedIndex = math.min(_selectedIndex, pendingItems.length - 1);
    final pendingItem = pendingItems[selectedIndex];
    _scheduleAdjacentPrefetch(pendingItems, selectedIndex);
    final provider = quickCollectionCardDetailControllerProvider(
      pendingItem.card.id,
    );
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final displayState = _isSavingAll && _savingDisplayState != null
        ? _savingDisplayState!
        : state;

    if (displayState.isLoading) {
      return const _QuickCollectionLoading();
    }
    if (displayState.isUnavailable) {
      return _QuickCollectionFailure(onRetry: controller.refresh);
    }
    if (displayState.assetStateStatus == KandoLoadStatus.loading) {
      return const _QuickCollectionLoading();
    }
    if (displayState.assetStateStatus == KandoLoadStatus.failure) {
      return _QuickCollectionFailure(onRetry: controller.refresh);
    }
    if (_activeItemId != pendingItem.id ||
        displayState.collectionItemDraft == null) {
      _initializeDraft(controller, pendingItem);
      return const _QuickCollectionLoading();
    }

    final multiple = pendingItems.length > 1;
    final sheet = _AddCollectionItemSheet(
      cardId: pendingItem.card.id,
      entrySource: AnalyticsValue.sourceSearch,
      useQuickCollectionController: true,
      stateOverride: _isSavingAll ? displayState : null,
      batchProgressText: _isSavingAll
          ? 'Saving $_savingCompletedCount of $_savingTotalCount'
          : null,
      actionsEnabled: !_isSavingAll,
      topContent: multiple
          ? _PendingCollectionStrip(
              items: pendingItems,
              selectedIndex: selectedIndex,
              enabled: !_isSavingAll,
              onSelected: (index) =>
                  _selectItem(controller, pendingItem, index),
              onClose: () {
                _captureDraft(
                  pendingItem.id,
                  ref.read(provider).collectionItemDraft,
                );
                controller.cancelCollectionItemEdit();
                context.pop();
              },
            )
          : null,
      onSaved: () => _completeCurrent(pendingItem.id),
      onDelete: () => _deleteCurrent(controller, pendingItem.id),
      onAddAll: multiple
          ? () {
              _captureDraft(
                pendingItem.id,
                ref.read(provider).collectionItemDraft,
              );
              return _saveAll();
            }
          : null,
      onDeleteAll: multiple ? _deleteAll : null,
    );
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        _captureDraft(pendingItem.id, ref.read(provider).collectionItemDraft);
        controller.cancelCollectionItemEdit();
      },
      child: sheet,
    );
  }

  void _scheduleAdjacentPrefetch(
    List<PendingCollectionItem> items,
    int selectedIndex,
  ) {
    final candidates = <PendingCollectionItem>[];
    for (var offset = 1; offset <= 2; offset += 1) {
      final index = selectedIndex + offset;
      if (index >= items.length) break;
      final item = items[index];
      if (_prefetchedCardIds.add(item.card.id)) candidates.add(item);
    }
    if (candidates.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final item in candidates) {
        ref.read(quickCollectionCardDetailControllerProvider(item.card.id));
        final imageUrl = item.card.imageUrl?.trim();
        if (imageUrl != null && imageUrl.isNotEmpty) {
          unawaited(
            precacheImage(NetworkImage(imageUrl), context, onError: (_, _) {}),
          );
        }
      }
    });
  }

  void _initializeDraft(
    CardDetailController controller,
    PendingCollectionItem item,
  ) {
    if (_initializingItemId == item.id) return;
    _initializingItemId = item.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prepareDraft(controller, item);
      setState(() {
        _activeItemId = item.id;
        _initializingItemId = null;
      });
    });
  }

  void _prepareDraft(
    CardDetailController controller,
    PendingCollectionItem item,
  ) {
    controller.cancelCollectionItemEdit();
    controller.startAddingCollectionItem();
    final storedDraft = item.draft;
    final quantityText = storedDraft == null
        ? item.quantity.toString()
        : storedDraft.quantityText;
    if (storedDraft == null) {
      controller.updateCollectionItemDraft(quantityText: quantityText);
    } else {
      _applyDraft(controller, storedDraft, quantityText: quantityText);
    }
  }

  Future<void> _completeCurrent(String itemId) async {
    ref.read(pendingCollectionProvider.notifier).remove(itemId);
    _activeItemId = null;
    if (!mounted) return;
    final remaining = ref.read(pendingCollectionProvider);
    if (remaining.isEmpty) {
      context.pop(1);
      return;
    }
    showKandoCenteredSuccessToast(
      context,
      message: portfolioCardAddedToastText,
    );
    setState(() {
      _selectedIndex = math.min(_selectedIndex, remaining.length - 1);
    });
  }

  void _deleteCurrent(CardDetailController controller, String itemId) {
    controller.cancelCollectionItemEdit();
    ref.read(pendingCollectionProvider.notifier).remove(itemId);
    _activeItemId = null;
    if (!mounted) return;
    final remaining = ref.read(pendingCollectionProvider);
    if (remaining.isEmpty) {
      context.pop();
      return;
    }
    setState(() {
      _selectedIndex = math.min(_selectedIndex, remaining.length - 1);
    });
  }

  void _selectItem(
    CardDetailController controller,
    PendingCollectionItem current,
    int index,
  ) {
    _captureDraft(
      current.id,
      ref
          .read(quickCollectionCardDetailControllerProvider(current.card.id))
          .collectionItemDraft,
    );
    controller.cancelCollectionItemEdit();
    final items = ref.read(pendingCollectionProvider);
    final next = items[index];
    final nextProvider = quickCollectionCardDetailControllerProvider(
      next.card.id,
    );
    final nextState = ref.read(nextProvider);
    final canActivateImmediately =
        !nextState.isLoading &&
        !nextState.isUnavailable &&
        nextState.assetStateStatus == KandoLoadStatus.content;
    if (canActivateImmediately) {
      _prepareDraft(ref.read(nextProvider.notifier), next);
    }
    setState(() {
      _activeItemId = canActivateImmediately ? next.id : null;
      _selectedIndex = index;
    });
  }

  void _captureDraft(String itemId, CardCollectionItemDraft? draft) {
    if (draft == null) return;
    ref
        .read(pendingCollectionProvider.notifier)
        .updateDraft(
          itemId,
          PendingCollectionDraft(
            quantityText: draft.quantityText,
            portfolioName: draft.portfolioName,
            grader: draft.grader,
            condition: draft.condition,
            grade: draft.grade,
            language: draft.language,
            finish: draft.finish,
            purchasePriceText: draft.purchasePriceText,
            notes: draft.notes,
          ),
        );
  }

  void _applyDraft(
    CardDetailController controller,
    PendingCollectionDraft draft, {
    required String quantityText,
  }) {
    controller.updateCollectionItemDraft(
      quantityText: quantityText,
      portfolioName: draft.portfolioName,
      grader: draft.grader,
      condition: draft.condition,
      grade: draft.grade,
      language: draft.language,
      finish: draft.finish,
      purchasePriceText: draft.purchasePriceText,
      notes: draft.notes,
    );
  }

  Future<void> _saveAll() async {
    if (_isSavingAll) return;
    final itemsToSave = List.of(ref.read(pendingCollectionProvider));
    if (itemsToSave.isEmpty) return;
    final selectedIndex = math.min(_selectedIndex, itemsToSave.length - 1);
    final selectedItem = itemsToSave[selectedIndex];
    final selectedState = ref.read(
      quickCollectionCardDetailControllerProvider(selectedItem.card.id),
    );
    setState(() {
      _isSavingAll = true;
      _savingDisplayState = selectedState;
      _savingCompletedCount = 0;
      _savingTotalCount = itemsToSave.length;
    });
    var closesWithSuccess = false;
    try {
      final groups = <String, List<PendingCollectionItem>>{};
      for (final item in itemsToSave) {
        groups.putIfAbsent(item.card.id, () => []).add(item);
      }
      final groupedItems = groups.values.toList();
      final savedByItemId = <String, bool>{};
      var nextGroupIndex = 0;

      Future<void> saveNextGroups() async {
        while (true) {
          final groupIndex = nextGroupIndex;
          if (groupIndex >= groupedItems.length) return;
          nextGroupIndex += 1;
          for (final item in groupedItems[groupIndex]) {
            var saved = false;
            try {
              saved = await _savePendingItem(item);
            } catch (_) {
              saved = false;
            }
            savedByItemId[item.id] = saved;
            if (!mounted) return;
            setState(() => _savingCompletedCount += 1);
          }
        }
      }

      await Future.wait(
        List.generate(
          math.min(3, groupedItems.length),
          (_) => saveNextGroups(),
        ),
      );
      if (!mounted) return;

      var successCount = 0;
      var failedCount = 0;
      String? firstFailedItemId;
      final savedItemIds = <String>[];
      for (final item in itemsToSave) {
        if (savedByItemId[item.id] == true) {
          successCount += 1;
          savedItemIds.add(item.id);
        } else {
          failedCount += 1;
          firstFailedItemId ??= item.id;
        }
      }
      if (successCount > 0) {
        _refreshAssetConsumersAfterBatch({
          for (final item in itemsToSave)
            if (savedByItemId[item.id] == true) item.card.id,
        });
      }
      final pendingController = ref.read(pendingCollectionProvider.notifier);
      for (final itemId in savedItemIds) {
        pendingController.remove(itemId);
      }
      if (failedCount == 0) {
        closesWithSuccess = true;
        context.pop(successCount);
      } else {
        if (firstFailedItemId != null) {
          _selectPendingItem(firstFailedItemId);
        }
        if (successCount > 0) {
          final cardLabel = successCount == 1 ? 'card' : 'cards';
          showKandoTopToast(
            context,
            message: '$successCount $cardLabel added, $failedCount failed.',
            type: KandoTopToastType.warning,
          );
        } else {
          showKandoTopToast(
            context,
            message: genericFailureToastText,
            type: KandoTopToastType.failure,
          );
        }
      }
    } finally {
      if (mounted && !closesWithSuccess) {
        setState(() {
          _isSavingAll = false;
          _savingDisplayState = null;
          _savingCompletedCount = 0;
          _savingTotalCount = 0;
        });
      }
    }
  }

  void _refreshAssetConsumersAfterBatch(Set<String> savedCardIds) {
    for (final cardId in savedCardIds) {
      ref.invalidate(cardDetailControllerProvider(cardId));
    }
    ref.invalidate(homeControllerProvider);
    ref.invalidate(homePerformanceControllerProvider);
    ref.invalidate(collectionControllerProvider);
    unawaited(
      ref.read(searchControllerProvider.notifier).refreshPreservingContent(),
    );
  }

  Future<bool> _savePendingItem(PendingCollectionItem item) async {
    final provider = quickCollectionCardDetailControllerProvider(item.card.id);
    ref.read(provider);
    final controller = ref.read(provider.notifier);
    await controller.loadComplete;
    if (!mounted) return false;

    final state = ref.read(provider);
    if (state.isUnavailable) return false;
    controller.cancelCollectionItemEdit();
    controller.startAddingCollectionItem();
    final storedDraft = item.draft;
    if (storedDraft == null) {
      controller.updateCollectionItemDraft(
        quantityText: item.quantity.toString(),
      );
    } else {
      _applyDraft(
        controller,
        storedDraft,
        quantityText: storedDraft.quantityText,
      );
    }
    if (ref.read(provider).collectionItemDraft == null) return false;
    return controller.saveCollectionItemDraft(
      idempotencyKey: item.id,
      invalidateAssetConsumers: false,
    );
  }

  void _selectPendingItem(String itemId, {bool keepControllerDraft = false}) {
    final index = ref
        .read(pendingCollectionProvider)
        .indexWhere((item) => item.id == itemId);
    if (index >= 0 && mounted) {
      setState(() {
        _activeItemId = keepControllerDraft ? itemId : null;
        _selectedIndex = index;
      });
    }
  }

  void _deleteAll() {
    final cardIds = {
      for (final item in ref.read(pendingCollectionProvider)) item.card.id,
    };
    for (final cardId in cardIds) {
      final provider = quickCollectionCardDetailControllerProvider(cardId);
      final state = ref.read(provider);
      if (!state.isLoading &&
          !state.isUnavailable &&
          state.collectionItemDraft != null) {
        ref.read(provider.notifier).cancelCollectionItemEdit();
      }
    }
    ref.read(pendingCollectionProvider.notifier).clear();
    context.pop();
  }
}

class _QuickCollectionLoading extends StatelessWidget {
  const _QuickCollectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFF222222),
      child: Center(
        child: CircularProgressIndicator(color: KandoColors.accent),
      ),
    );
  }
}

class _QuickCollectionFailure extends StatelessWidget {
  const _QuickCollectionFailure({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF222222),
      child: Center(
        child: FilledButton(onPressed: onRetry, child: const Text('Try again')),
      ),
    );
  }
}

class _PendingCollectionStrip extends StatelessWidget {
  const _PendingCollectionStrip({
    required this.items,
    required this.selectedIndex,
    required this.enabled,
    required this.onSelected,
    required this.onClose,
  });

  final List<PendingCollectionItem> items;
  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('pending-collection-card-strip'),
      height: 70,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return InkWell(
                  key: Key('pending-collection-item-${item.id}'),
                  onTap: enabled ? () => onSelected(index) : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 40,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: index == selectedIndex
                            ? KandoColors.accent
                            : KandoColors.border,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: KandoCardImage(imageUrl: item.card.imageUrl),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            key: const Key('pending-collection-close'),
            tooltip: 'Close',
            onPressed: enabled ? onClose : null,
            icon: const Icon(Icons.close, color: KandoColors.mutedText),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _AddCollectionItemSheet extends ConsumerWidget {
  const _AddCollectionItemSheet({
    required this.cardId,
    required this.entrySource,
    this.topContent,
    this.onSaved,
    this.onDelete,
    this.onAddAll,
    this.onDeleteAll,
    this.actionsEnabled = true,
    this.useQuickCollectionController = false,
    this.stateOverride,
    this.batchProgressText,
  });

  final String cardId;
  final String entrySource;
  final Widget? topContent;
  final Future<void> Function()? onSaved;
  final VoidCallback? onDelete;
  final Future<void> Function()? onAddAll;
  final VoidCallback? onDeleteAll;
  final bool actionsEnabled;
  final bool useQuickCollectionController;
  final CardDetailState? stateOverride;
  final String? batchProgressText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = useQuickCollectionController
        ? quickCollectionCardDetailControllerProvider(cardId)
        : cardDetailControllerProvider(cardId);
    final providerState = ref.watch(provider);
    final state = stateOverride ?? providerState;
    final controller = ref.read(provider.notifier);
    if (state.isLoading ||
        state.isUnavailable ||
        state.collectionItemDraft == null) {
      return const SizedBox.shrink();
    }
    final draft = state.collectionItemDraft!;
    final hidesPortfolioSelector = entrySource == AnalyticsValue.sourceSearch;

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
              if (topContent != null) topContent!,
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
                      child: InkWell(
                        key: const Key('card-detail-add-item-portfolio'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: actionsEnabled
                            ? () async {
                                final options = [
                                  for (final folder
                                      in state.detail.portfolioFolders)
                                    folder.name,
                                ];
                                final next = await _showChoiceSheet(
                                  context,
                                  title: 'Portfolio',
                                  selected: draft.portfolioName,
                                  options: options,
                                );
                                if (next != null) {
                                  controller.updateCollectionItemDraft(
                                    portfolioName: next,
                                  );
                                }
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: KandoColors.accent,
                              ),
                            ],
                          ),
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
                          padding: const EdgeInsets.all(20),
                          child: IgnorePointer(
                            ignoring: !actionsEnabled,
                            child: _CollectionItemForm(
                              state: state,
                              controller: controller,
                              embedded: true,
                              showHeader: false,
                              showTotal: false,
                              showActions: false,
                              showPortfolioSelector: !hidesPortfolioSelector,
                            ),
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
                          key: const Key('card-detail-item-total'),
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
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('card-detail-item-submit'),
                            style: FilledButton.styleFrom(
                              backgroundColor: KandoColors.accent,
                              disabledBackgroundColor: KandoColors.accent,
                              foregroundColor: KandoColors.ink,
                              disabledForegroundColor: KandoColors.ink,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                            onPressed:
                                state.isSavingCollectionItemDraft ||
                                    !actionsEnabled
                                ? null
                                : () async {
                                    ref
                                        .read(analyticsProvider)
                                        .track(
                                          AnalyticsEvent.collectionItemAddClick,
                                          properties: {
                                            AnalyticsProperty.ipType:
                                                analyticsIpType(
                                                  state.detail.game,
                                                ),
                                            AnalyticsProperty.gradeType:
                                                draft.grader.toLowerCase() ==
                                                    'raw'
                                                ? AnalyticsValue.gradeNormal
                                                : AnalyticsValue.gradeGraded,
                                            AnalyticsProperty.entrySource:
                                                entrySource,
                                          },
                                        );
                                    bool saved;
                                    try {
                                      saved = await controller
                                          .saveCollectionItemDraft();
                                    } on PortfolioApiException catch (error) {
                                      if (context.mounted) {
                                        showKandoTopToast(
                                          context,
                                          message: error.message,
                                          type: KandoTopToastType.failure,
                                        );
                                      }
                                      return;
                                    } catch (_) {
                                      if (context.mounted) {
                                        showKandoTopFailureToast(context);
                                      }
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    if (!saved) {
                                      final message = ref
                                          .read(provider)
                                          .collectionItemFormError;
                                      showKandoTopToast(
                                        context,
                                        message:
                                            message ?? genericFailureToastText,
                                        type: KandoTopToastType.failure,
                                      );
                                      return;
                                    }
                                    if (onSaved != null) {
                                      await onSaved!();
                                    } else {
                                      Navigator.of(context).pop(true);
                                    }
                                  },
                            icon: state.isSavingCollectionItemDraft
                                ? const SizedBox(
                                    key: Key('card-detail-item-submit-loading'),
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: KandoColors.ink,
                                    ),
                                  )
                                : const Icon(Icons.add_circle_outline),
                            label: const Text('Add this card'),
                          ),
                        ),
                        if (onDelete != null) ...[
                          const SizedBox(width: 10),
                          IconButton.filled(
                            key: const Key('pending-collection-delete'),
                            tooltip: 'Delete pending item',
                            onPressed: actionsEnabled ? onDelete : null,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF33282C),
                              foregroundColor: const Color(0xFFE58B93),
                              fixedSize: const Size.square(52),
                            ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                    if (onAddAll != null && onDeleteAll != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('pending-collection-add-all'),
                              onPressed: actionsEnabled ? onAddAll : null,
                              child: Text(batchProgressText ?? 'ADD ALL CARDS'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('pending-collection-delete-all'),
                              onPressed: actionsEnabled ? onDeleteAll : null,
                              child: const Text('DELETE ALL CARDS'),
                            ),
                          ),
                        ],
                      ),
                    ],
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
              child: KandoCardImage(imageUrl: detail.imageUrl),
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
    super.key,
    required this.state,
    required this.controller,
    this.embedded = false,
    this.showHeader = true,
    this.showTotal = true,
    this.showActions = true,
    this.showPortfolioSelector = true,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final bool embedded;
  final bool showHeader;
  final bool showTotal;
  final bool showActions;
  final bool showPortfolioSelector;

  @override
  Widget build(BuildContext context) {
    final draft = state.collectionItemDraft;
    final isEditing = state.editingCollectionItemId != null;
    if (draft == null) {
      return const SizedBox.shrink();
    }
    final saving = state.isSavingCollectionItemDraft;
    final languageOptions = _optionsWithSelected(
      state.detail.collectionLanguageOptions,
      draft.language,
    );
    final finishOptions = _optionsWithSelected(
      state.detail.collectionFinishOptions,
      draft.finish,
    );
    final languageValue = languageOptions.contains(draft.language)
        ? draft.language
        : languageOptions.first;
    final finishValue = finishOptions.contains(draft.finish)
        ? draft.finish
        : finishOptions.first;
    final gradeOptions = cardCollectionGradeValuesFor(draft.grader);
    final gradeValue = gradeOptions.contains(draft.grade)
        ? draft.grade
        : gradeOptions.firstOrNull ?? '10';
    final useEditCard = isEditing && showHeader && showActions && !embedded;

    if (useEditCard) {
      return _CollectionItemEditCard(
        state: state,
        controller: controller,
        draft: draft,
        languageValue: languageValue,
        finishValue: finishValue,
        languageOptions: languageOptions,
        finishOptions: finishOptions,
        gradeValue: gradeValue,
      );
    }

    if (!isEditing && embedded) {
      return _CollectionItemAddForm(
        state: state,
        controller: controller,
        draft: draft,
        languageValue: languageValue,
        finishValue: finishValue,
        languageOptions: languageOptions,
        finishOptions: finishOptions,
        gradeValue: gradeValue,
        showPortfolioSelector: showPortfolioSelector,
      );
    }

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
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: (value) {
              controller.updateCollectionItemDraft(quantityText: value);
            },
          ),
          const SizedBox(height: 12),
          _ChoiceField(
            key: const Key('card-detail-item-grader'),
            label: 'Grader',
            value: draft.grader,
            options: cardCollectionGraders,
            onSelected: (value) async {
              controller.updateCollectionItemDraft(grader: value);
              if (value == 'Raw') return;

              final grade = await _showChoiceSheet(
                context,
                title: 'Grade',
                selected: cardCollectionGradeValuesFor(value).first,
                options: cardCollectionGradeValuesFor(value),
              );
              if (grade != null) {
                controller.updateCollectionItemDraft(grade: grade);
              }
            },
          ),
          const SizedBox(height: 12),
          if (draft.isRaw)
            _ChoiceField(
              key: const Key('card-detail-item-condition'),
              label: 'Condition',
              value: draft.condition,
              options: cardCollectionConditions,
              onSelected: (value) {
                controller.updateCollectionItemDraft(condition: value);
              },
            )
          else
            _ChoiceField(
              key: const Key('card-detail-item-grade'),
              label: 'Grade',
              value: gradeValue,
              options: gradeOptions,
              displayBuilder: (grade) => '${draft.grader} $grade',
              onSelected: (value) {
                controller.updateCollectionItemDraft(grade: value);
              },
            ),
          const SizedBox(height: 12),
          _ChoiceField(
            key: const Key('card-detail-item-language'),
            label: 'Language',
            value: languageValue,
            options: languageOptions,
            onSelected: (value) async {
              controller.updateCollectionItemDraft(language: value);
              await controller.selectCollectionPriceLanguage(value);
            },
          ),
          const SizedBox(height: 12),
          _ChoiceField(
            key: const Key('card-detail-item-finish'),
            label: 'Finish',
            value: finishValue,
            options: finishOptions,
            onSelected: (value) async {
              controller.updateCollectionItemDraft(finish: value);
              await controller.selectPriceFinish(value);
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
                  onPressed: () {
                    _trackFromContext(context, AnalyticsEvent.cancelClick);
                    controller.cancelCollectionItemEdit();
                  },
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
                  onPressed: saving
                      ? null
                      : () async {
                          await controller.saveCollectionItemDraft();
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KandoColors.ink,
                          ),
                        )
                      : Icon(isEditing ? Icons.save_outlined : Icons.add),
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

class _CollectionItemAddForm extends StatelessWidget {
  const _CollectionItemAddForm({
    required this.state,
    required this.controller,
    required this.draft,
    required this.languageValue,
    required this.finishValue,
    required this.languageOptions,
    required this.finishOptions,
    required this.gradeValue,
    required this.showPortfolioSelector,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final CardCollectionItemDraft draft;
  final String languageValue;
  final String finishValue;
  final List<String> languageOptions;
  final List<String> finishOptions;
  final String gradeValue;
  final bool showPortfolioSelector;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('OWNERSHIP SUMMARY', style: _kCollectionEditLabelStyle),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _CollectionEditTextField(
                key: const Key('card-detail-item-quantity'),
                label: 'QUANTITY',
                initialValue: draft.quantityText,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  controller.updateCollectionItemDraft(quantityText: value);
                },
              ),
            ),
            if (showPortfolioSelector) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _ChoiceField(
                  key: const Key('card-detail-item-portfolio'),
                  label: 'PORTFOLIO',
                  value: draft.portfolioName,
                  options: [
                    for (final folder in state.detail.portfolioFolders)
                      folder.name,
                  ],
                  onSelected: (value) {
                    controller.updateCollectionItemDraft(portfolioName: value);
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        _CollectionPillGroup(
          key: const Key('card-detail-item-finish'),
          label: 'FINISH',
          selected: finishValue,
          options: finishOptions,
          columns: 3,
          onSelected: (value) async {
            controller.updateCollectionItemDraft(finish: value);
            await controller.selectPriceFinish(value);
          },
        ),
        const SizedBox(height: 24),
        _CollectionCardStateSelector(
          isRaw: draft.isRaw,
          onRawSelected: () {
            controller.updateCollectionItemDraft(grader: 'Raw');
          },
          onGradedSelected: () {
            controller.updateCollectionItemDraft(
              grader: draft.isRaw ? 'PSA' : draft.grader,
              grade: cardCollectionGradeValuesFor(
                draft.isRaw ? 'PSA' : draft.grader,
              ).first,
            );
          },
        ),
        const SizedBox(height: 32),
        const Divider(height: 1, color: _kCollectionOutline),
        const SizedBox(height: 24),
        _CollectionDetailsHeading(isRaw: draft.isRaw),
        const SizedBox(height: 24),
        if (draft.isRaw)
          _CollectionPillGroup(
            key: const Key('card-detail-item-condition'),
            label: 'CONDITION',
            selected: draft.condition,
            options: _optionsWithSelected(
              _kEditConditionOptions,
              draft.condition,
            ),
            columns: 1,
            onSelected: (value) {
              controller.updateCollectionItemDraft(condition: value);
            },
          )
        else ...[
          _CollectionPillGroup(
            key: const Key('card-detail-item-grader'),
            label: 'GRADER',
            selected: draft.grader,
            options: _optionsWithSelected(
              _kEditGraderOptions.where((value) => value != 'Raw').toList(),
              draft.grader,
            ),
            columns: 3,
            onSelected: (value) {
              controller.updateCollectionItemDraft(grader: value);
            },
          ),
          const SizedBox(height: 24),
          _CollectionPillGroup(
            key: const Key('card-detail-item-grade'),
            label: 'GRADE',
            selected: gradeValue,
            options: cardCollectionGradeValuesFor(draft.grader),
            columns: 3,
            onSelected: (value) {
              controller.updateCollectionItemDraft(grade: value);
            },
          ),
        ],
        const SizedBox(height: 24),
        _ChoiceField(
          key: const Key('card-detail-item-language'),
          label: 'LANGUAGE',
          value: languageValue,
          options: languageOptions,
          onSelected: (value) async {
            controller.updateCollectionItemDraft(language: value);
            await controller.selectCollectionPriceLanguage(value);
          },
        ),
        const SizedBox(height: 24),
        _CollectionEditTextField(
          key: const Key('card-detail-item-purchase-price'),
          label: 'PURCHASE PRICE',
          initialValue: draft.purchasePriceText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          accentText: true,
          onChanged: (value) {
            controller.updateCollectionItemDraft(purchasePriceText: value);
          },
        ),
        const SizedBox(height: 32),
        const Divider(height: 1, color: _kCollectionOutline),
        const SizedBox(height: 32),
        const Text('NOTES', style: _kCollectionHeadlineStyle),
        const SizedBox(height: 12),
        _CollectionEditTextArea(
          key: const Key('card-detail-item-notes'),
          initialValue: draft.notes,
          onChanged: (value) {
            controller.updateCollectionItemDraft(notes: value);
          },
        ),
        if (state.collectionItemFormError != null) ...[
          const SizedBox(height: 12),
          Text(
            state.collectionItemFormError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _CollectionItemEditCard extends StatelessWidget {
  const _CollectionItemEditCard({
    required this.state,
    required this.controller,
    required this.draft,
    required this.languageValue,
    required this.finishValue,
    required this.languageOptions,
    required this.finishOptions,
    required this.gradeValue,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final CardCollectionItemDraft draft;
  final String languageValue;
  final String finishValue;
  final List<String> languageOptions;
  final List<String> finishOptions;
  final String gradeValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kCollectionCardStart, _kCollectionCardEnd],
        ),
        borderRadius: BorderRadius.circular(_kRadiusLg),
        border: Border.all(color: _kCollectionOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('OWNERSHIP SUMMARY', style: _kCollectionEditLabelStyle),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CollectionEditTextField(
                  key: const Key('card-detail-item-quantity'),
                  label: 'QUANTITY',
                  initialValue: draft.quantityText,
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    controller.updateCollectionItemDraft(quantityText: value);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ChoiceField(
                  key: const Key('card-detail-item-portfolio'),
                  label: 'PORTFOLIO',
                  value: draft.portfolioName,
                  options: [
                    for (final folder in state.detail.portfolioFolders)
                      folder.name,
                  ],
                  onSelected: (value) {
                    controller.updateCollectionItemDraft(portfolioName: value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(height: 1, thickness: 1, color: _kCollectionOutline),
          const SizedBox(height: 24),
          _CollectionPillGroup(
            key: const Key('card-detail-item-finish'),
            label: 'FINISH',
            selected: finishValue,
            options: finishOptions,
            columns: 3,
            onSelected: (value) async {
              controller.updateCollectionItemDraft(finish: value);
              await controller.selectPriceFinish(value);
            },
          ),
          const SizedBox(height: 24),
          _CollectionCardStateSelector(
            isRaw: draft.isRaw,
            onRawSelected: () {
              controller.updateCollectionItemDraft(grader: 'Raw');
            },
            onGradedSelected: () {
              final grader = draft.isRaw ? 'PSA' : draft.grader;
              controller.updateCollectionItemDraft(
                grader: grader,
                grade: cardCollectionGradeValuesFor(grader).first,
              );
            },
          ),
          const SizedBox(height: 32),
          const Divider(height: 1, thickness: 1, color: _kCollectionOutline),
          const SizedBox(height: 24),
          _CollectionDetailsHeading(isRaw: draft.isRaw),
          const SizedBox(height: 24),
          if (draft.isRaw)
            _CollectionPillGroup(
              key: const Key('card-detail-item-condition'),
              label: 'CONDITION',
              selected: draft.condition,
              options: _optionsWithSelected(
                _kEditConditionOptions,
                draft.condition,
              ),
              columns: 1,
              onSelected: (value) {
                controller.updateCollectionItemDraft(condition: value);
              },
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CollectionPillGroup(
                  key: const Key('card-detail-item-grader'),
                  label: 'GRADER',
                  selected: draft.grader,
                  options: _optionsWithSelected(
                    _kEditGraderOptions
                        .where((value) => value != 'Raw')
                        .toList(),
                    draft.grader,
                  ),
                  columns: 3,
                  onSelected: (value) {
                    controller.updateCollectionItemDraft(grader: value);
                  },
                ),
                const SizedBox(height: 24),
                _CollectionPillGroup(
                  key: const Key('card-detail-item-grade'),
                  label: 'GRADE',
                  selected: gradeValue,
                  options: cardCollectionGradeValuesFor(draft.grader),
                  columns: 3,
                  onSelected: (value) {
                    controller.updateCollectionItemDraft(grade: value);
                  },
                ),
              ],
            ),
          const SizedBox(height: 24),
          _ChoiceField(
            key: const Key('card-detail-item-language'),
            label: 'LANGUAGE',
            value: languageValue,
            options: languageOptions,
            onSelected: (value) async {
              controller.updateCollectionItemDraft(language: value);
              await controller.selectCollectionPriceLanguage(value);
            },
          ),
          const SizedBox(height: 24),
          _CollectionEditTextField(
            key: const Key('card-detail-item-purchase-price'),
            label: 'PURCHASE PRICE',
            initialValue: draft.purchasePriceText,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            accentText: true,
            onChanged: (value) {
              controller.updateCollectionItemDraft(purchasePriceText: value);
            },
          ),
          const SizedBox(height: 32),
          const Text('NOTES', style: _kCollectionHeadlineStyle),
          const SizedBox(height: 12),
          _CollectionEditTextArea(
            key: const Key('card-detail-item-notes'),
            initialValue: draft.notes,
            onChanged: (value) {
              controller.updateCollectionItemDraft(notes: value);
            },
          ),
          if (state.collectionItemFormError != null) ...[
            const SizedBox(height: 12),
            Text(
              state.collectionItemFormError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _CollectionDetailsHeading extends StatelessWidget {
  const _CollectionDetailsHeading({required this.isRaw});

  final bool isRaw;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            isRaw ? 'RAW DETAILS' : 'GRADING DETAILS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _kCollectionHeadlineStyle,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: KandoColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isRaw ? 'Raw details' : 'Third-party graded',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: KandoColors.mutedText),
          ),
        ),
      ],
    );
  }
}

class _CollectionEditFooter extends StatelessWidget {
  const _CollectionEditFooter({required this.state, required this.controller});

  final CardDetailState state;
  final CardDetailController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('card-detail-item-edit-footer'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: const BoxDecoration(
          color: KandoColors.ink,
          border: Border(top: BorderSide(color: _kCollectionOutline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: TextButton(
                  onPressed: state.isSavingCollectionItemDraft
                      ? null
                      : () {
                          _trackFromContext(
                            context,
                            AnalyticsEvent.cancelClick,
                          );
                          controller.cancelCollectionItemEdit();
                        },
                  style: TextButton.styleFrom(
                    backgroundColor: KandoColors.elevatedSurface,
                    foregroundColor: KandoColors.text,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('CANCEL'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 56,
                child: TextButton(
                  key: const Key('card-detail-item-submit'),
                  onPressed: state.isSavingCollectionItemDraft
                      ? null
                      : () async {
                          await controller.saveCollectionItemDraft();
                        },
                  style: TextButton.styleFrom(
                    backgroundColor: KandoColors.accent,
                    foregroundColor: KandoColors.primaryOnDefault,
                    shape: const StadiumBorder(),
                  ),
                  child: state.isSavingCollectionItemDraft
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KandoColors.primaryOnDefault,
                          ),
                        )
                      : const Text('SAVE CHANGES'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionEditTextField extends StatelessWidget {
  const _CollectionEditTextField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.keyboardType,
    this.accentText = false,
    super.key,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final bool accentText;

  @override
  Widget build(BuildContext context) {
    return _CollectionEditLabeledControl(
      label: label,
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        cursorColor: KandoColors.accent,
        style: TextStyle(
          fontSize: 16,
          height: 24 / 16,
          fontWeight: accentText ? FontWeight.w600 : FontWeight.w400,
          color: accentText ? KandoColors.accent : KandoColors.text,
        ),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
        ),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        onChanged: onChanged,
      ),
    );
  }
}

class _CollectionEditTextArea extends StatelessWidget {
  const _CollectionEditTextArea({
    required this.initialValue,
    required this.onChanged,
    super.key,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 17),
      decoration: BoxDecoration(
        color: KandoColors.ink,
        borderRadius: BorderRadius.circular(_kRadiusLg),
        border: Border.all(color: KandoColors.border),
      ),
      child: TextFormField(
        initialValue: initialValue,
        cursorColor: KandoColors.accent,
        minLines: 5,
        maxLines: 8,
        style: const TextStyle(
          fontSize: 14,
          height: 20 / 14,
          color: KandoColors.text,
        ),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
        ),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        onChanged: onChanged,
      ),
    );
  }
}

class _CollectionEditLabeledControl extends StatelessWidget {
  const _CollectionEditLabeledControl({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: _kCollectionEditLabelStyle),
        const SizedBox(height: 8),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
          decoration: BoxDecoration(
            color: KandoColors.ink,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KandoColors.border),
          ),
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ],
    );
  }
}

class _CollectionPillGroup extends StatelessWidget {
  const _CollectionPillGroup({
    required this.label,
    required this.selected,
    required this.options,
    required this.columns,
    required this.onSelected,
    super.key,
  });

  final String label;
  final String? selected;
  final List<String> options;
  final int columns;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: _kCollectionEditLabelStyle),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final gap = columns == 1 ? 0.0 : 8.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 8,
              children: [
                for (final option in options)
                  SizedBox(
                    width: width,
                    height: 44,
                    child: _CollectionPillButton(
                      label: option,
                      selected: option == selected,
                      alignLeft: columns == 1,
                      onPressed: () => onSelected(option),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CollectionCardStateSelector extends StatelessWidget {
  const _CollectionCardStateSelector({
    required this.isRaw,
    required this.onRawSelected,
    required this.onGradedSelected,
  });

  final bool isRaw;
  final VoidCallback onRawSelected;
  final VoidCallback onGradedSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('card-detail-item-card-state'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('CARD STATE', style: _kCollectionEditLabelStyle),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CollectionCardStateButton(
                buttonKey: const Key('card-detail-item-state-raw'),
                title: 'Raw',
                subtitle: 'Unrated card',
                selected: isRaw,
                onPressed: onRawSelected,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CollectionCardStateButton(
                buttonKey: const Key('card-detail-item-state-graded'),
                title: 'Graded',
                subtitle: 'Certified card',
                selected: !isRaw,
                onPressed: onGradedSelected,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CollectionCardStateButton extends StatelessWidget {
  const _CollectionCardStateButton({
    required this.buttonKey,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
  });

  final Key buttonKey;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: buttonKey,
      color: selected
          ? KandoColors.accent.withValues(alpha: 0.1)
          : KandoColors.ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? KandoColors.accent : KandoColors.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? KandoColors.accent
                        : _kCollectionSecondaryText,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _kCollectionSecondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionPillButton extends StatelessWidget {
  const _CollectionPillButton({
    required this.label,
    required this.selected,
    required this.alignLeft,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool alignLeft;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? KandoColors.accent.withValues(alpha: 0.1)
          : KandoColors.ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? KandoColors.accent : KandoColors.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                height: 24 / 16,
                color: selected
                    ? KandoColors.accent
                    : _kCollectionSecondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const TextStyle _kCollectionEditLabelStyle = TextStyle(
  fontSize: 11,
  height: 18 / 11,
  color: _kCollectionSecondaryText,
);

List<String> _optionsWithSelected(List<String> options, String? selected) {
  if (selected == null || selected.isEmpty || options.contains(selected)) {
    return options;
  }
  return [...options, selected];
}

class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.displayBuilder,
    super.key,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final String Function(String value)? displayBuilder;

  @override
  Widget build(BuildContext context) {
    final selected = options.contains(value) ? value! : options.first;
    final displayText = displayBuilder?.call(selected) ?? selected;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final next = await _showChoiceSheet(
          context,
          title: label,
          selected: selected,
          options: options,
        );
        if (next != null) {
          onSelected(next);
        }
      },
      child: _CollectionEditLabeledControl(
        label: label,
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KandoColors.text,
                  fontSize: 16,
                  height: 24 / 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 21,
              color: KandoColors.disabledText,
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showChoiceSheet(
  BuildContext context, {
  required String title,
  required String selected,
  required List<String> options,
}) {
  FocusManager.instance.primaryFocus?.unfocus(
    disposition: UnfocusDisposition.scope,
  );
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    requestFocus: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final screenHeight = MediaQuery.sizeOf(sheetContext).height;
      final bottomInset = MediaQuery.paddingOf(sheetContext).bottom;
      final maxHeight = math.min(screenHeight * 0.68, 520.0);

      return SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Material(
              key: const Key('card-detail-choice-sheet'),
              color: const Color(0xFF191A12),
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              height: 32 / 24,
                              color: KandoColors.text,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: KandoColors.mutedText,
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.fromLTRB(10, 0, 10, 12 + bottomInset),
                      itemCount: options.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final isSelected = option == selected;
                        return _ChoiceSheetOption(
                          option: option,
                          selected: isSelected,
                          onTap: () => Navigator.of(sheetContext).pop(option),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ChoiceSheetOption extends StatelessWidget {
  const _ChoiceSheetOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final String option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? KandoColors.accent.withValues(alpha: 0.16)
              : KandoColors.surface.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? KandoColors.accent.withValues(alpha: 0.8)
                : KandoColors.border.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? KandoColors.text : KandoColors.mutedText,
                  fontSize: 15,
                  height: 22 / 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 20,
              color: selected
                  ? KandoColors.accent
                  : KandoColors.border.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceOverview extends ConsumerWidget {
  const _PriceOverview({
    required this.state,
    required this.controller,
    required this.isPro,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final bool isPro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chartSeries = [
      for (
        var index = 0;
        index < state.selectedPriceChartSeries.length;
        index++
      )
        _DetailChartSeries(
          label: state.selectedPriceChartSeries[index].label,
          points:
              state.selectedPriceChartSeries[index].seriesByRange[state
                  .selectedPriceRange] ??
              const [],
          color: _kPriceChartColors[index % _kPriceChartColors.length],
        ),
    ].where((series) => series.points.length >= 2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Price',
          key: Key('card-detail-price-heading'),
          style: _kSectionTitleStyle,
        ),
        if (state.priceFinishes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _FinishTabs(
            finishes: state.priceFinishes,
            selected: state.priceFinish,
            onSelected: controller.selectPriceFinish,
          ),
          const SizedBox(height: 16),
        ],
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
              if (chartSeries.length > 1) ...[
                _PriceChartLegend(series: chartSeries),
                const SizedBox(height: 16),
              ],
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
                    : chartSeries.isEmpty
                    ? Center(
                        child: Text(
                          state.priceSeriesFallbackText,
                          style: const TextStyle(color: KandoColors.mutedText),
                        ),
                      )
                    : _InteractivePriceChart(series: chartSeries),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final range in CardPriceRange.values)
                    _PriceRangeButton(
                      range: range,
                      selected: state.selectedPriceRange == range,
                      showProBadge: !isPro && range == CardPriceRange.oneYear,
                      onSelected: (range) => _selectRange(context, ref, range),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Market Prices', style: _kSectionTitleStyle),
        const SizedBox(height: 12),
        _MarketPriceCategories(
          selected: state.selectedMarketPriceCategory,
          categories: state.availableMarketPriceCategories,
          onSelected: controller.selectMarketPriceCategory,
        ),
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
              imageUrl: state.detail.imageUrl,
              onTap: row.url == null
                  ? null
                  : () async {
                      try {
                        await ref
                            .read(cardDetailActionsProvider)
                            .openMarketplaceListing(row.url!);
                      } catch (_) {
                        if (context.mounted) {
                          showKandoTopFailureToast(context);
                        }
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

  Future<void> _selectRange(
    BuildContext context,
    WidgetRef ref,
    CardPriceRange range,
  ) async {
    if (range == CardPriceRange.oneYear && !isPro) {
      final premiumState = await _resolvePremiumForRestrictedAction(ref);
      if (!context.mounted || premiumState == AppPremiumState.unknown) return;
      if (premiumState == AppPremiumState.premium) {
        final selected = await controller.selectPriceRange(range);
        if (!selected && context.mounted) {
          showKandoTopFailureToast(context);
        }
        return;
      }
      final result = await context.push<SubscriptionPaywallResult>(
        subscriptionSheetLocation,
      );
      if (!context.mounted || result == null) return;
      if (result == SubscriptionPaywallResult.premiumRestored) {
        showSubscriptionRestoreResult(
          context,
          type: SubscriptionRestoreResultType.premiumRestored,
        );
      } else {
        showPremiumUnlockedToast(context);
      }
    }
    final selected = await controller.selectPriceRange(range);
    if (!selected && context.mounted) showKandoTopFailureToast(context);
  }
}

Future<AppPremiumState> _resolvePremiumForRestrictedAction(WidgetRef ref) {
  final current = ref.read(subscriptionControllerProvider).premiumState;
  if (current != AppPremiumState.unknown) return Future.value(current);
  return ref.read(subscriptionControllerProvider.notifier).refreshEntitlement();
}

class _FinishTabs extends StatefulWidget {
  const _FinishTabs({
    required this.finishes,
    required this.selected,
    required this.onSelected,
  });

  final List<String> finishes;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<_FinishTabs> createState() => _FinishTabsState();
}

class _FinishTabsState extends State<_FinishTabs> {
  static const _textStyle = TextStyle(fontSize: 15, height: 17 / 15);
  final ScrollController _scrollController = ScrollController();
  bool _showEndFade = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateEndFade);
    _scheduleEndFadeUpdate();
  }

  @override
  void didUpdateWidget(covariant _FinishTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleEndFadeUpdate();
  }

  void _scheduleEndFadeUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEndFade());
  }

  void _updateEndFade() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final show = position.maxScrollExtent > position.pixels + 0.5;
    if (show != _showEndFade) setState(() => _showEndFade = show);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateEndFade)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: SizedBox(
          key: const Key('card-detail-finish-tabs'),
          height: 44,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabs = [
                for (final finish in widget.finishes) _buildTab(finish),
              ];
              if (_tabsWidth(context) <= constraints.maxWidth) {
                return Row(children: tabs);
              }
              _scheduleEndFadeUpdate();
              return Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      key: const Key('card-detail-finish-tabs-scroll'),
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: tabs,
                      ),
                    ),
                  ),
                  if (_showEndFade)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          key: const Key('card-detail-finish-tabs-end-fade'),
                          width: 40,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, KandoColors.ink],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  double _tabsWidth(BuildContext context) {
    var width = 0.0;
    for (final finish in widget.finishes) {
      final painter = TextPainter(
        text: TextSpan(text: finish, style: _textStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      width += painter.width + 44;
      painter.dispose();
    }
    return width;
  }

  Widget _buildTab(String finish) {
    final selected = finish == widget.selected;
    return InkWell(
      key: Key('card-detail-finish-$finish'),
      borderRadius: BorderRadius.circular(4),
      onTap: selected ? null : () => widget.onSelected(finish),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? KandoColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FinishIcon(
              key: Key('card-detail-finish-icon-$finish'),
              pattern: _finishIconPattern(
                finish,
                randomize: widget.finishes.length > 2,
              ),
              color: selected ? KandoColors.accent : KandoColors.mutedText,
            ),
            const SizedBox(width: 4),
            Text(
              finish,
              maxLines: 1,
              softWrap: false,
              style: _textStyle.copyWith(
                color: selected ? KandoColors.accent : KandoColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _FinishIconPattern { circle, heart, diamond, sparkle }

_FinishIconPattern _finishIconPattern(
  String finish, {
  required bool randomize,
}) {
  if (!randomize) {
    return finish.toLowerCase().contains('foil')
        ? _FinishIconPattern.heart
        : _FinishIconPattern.circle;
  }

  final hash = finish.codeUnits.fold<int>(
    0,
    (value, codeUnit) => (value * 31 + codeUnit) & 0x7fffffff,
  );
  return _FinishIconPattern.values[hash % _FinishIconPattern.values.length];
}

class _FinishIcon extends StatelessWidget {
  const _FinishIcon({super.key, required this.pattern, required this.color});

  final _FinishIconPattern pattern;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = switch (pattern) {
      _FinishIconPattern.circle => Icons.circle_outlined,
      _FinishIconPattern.heart => Icons.favorite,
      _FinishIconPattern.diamond => Icons.diamond,
      _FinishIconPattern.sparkle => Icons.auto_awesome,
    };

    return SizedBox.square(
      dimension: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 10.5,
            height: 14,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 0.875),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          Icon(icon, size: 5.5, color: color),
        ],
      ),
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
    required this.showProBadge,
    required this.onSelected,
  });

  final CardPriceRange range;
  final bool selected;
  final bool showProBadge;
  final ValueChanged<CardPriceRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('card-detail-price-range-${range.label}'),
      borderRadius: BorderRadius.circular(4),
      onTap: () => onSelected(range),
      child: showProBadge
          ? SizedBox(
              width: 70,
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    range.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: KandoColors.mutedText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    key: const Key('card-detail-price-range-1y-pro-badge'),
                    width: 35,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KandoColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        color: KandoColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 18 / 12,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : _PriceRangeIndicator(range: range, selected: selected),
    );
  }
}

class _PriceRangeIndicator extends StatelessWidget {
  const _PriceRangeIndicator({required this.range, required this.selected});

  final CardPriceRange range;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Container(
          width: 40,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99747B26), Color(0x33747B26)],
                  )
                : null,
            boxShadow: selected
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
              fontSize: 10,
              color: selected ? KandoColors.accent : KandoColors.mutedText,
            ),
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
          if (rows.isEmpty)
            const _MarketPricesRow(grade: '--', market: '--', change: '-/-'),
        ],
      ),
    );
  }
}

class _MarketPriceCategories extends StatelessWidget {
  const _MarketPriceCategories({
    required this.selected,
    required this.categories,
    required this.onSelected,
  });

  final CardMarketPriceCategory selected;
  final List<CardMarketPriceCategory> categories;
  final ValueChanged<CardMarketPriceCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 8,
      children: [
        for (final category in categories)
          InkWell(
            key: Key('card-detail-market-category-${category.name}'),
            borderRadius: BorderRadius.circular(999),
            onTap: () => onSelected(category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected == category
                    ? const Color(0xFFBAC158)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected == category
                      ? const Color(0xFFBAC158)
                      : KandoColors.border,
                ),
              ),
              child: Text(
                category.label,
                style: TextStyle(
                  fontSize: 10,
                  color: selected == category
                      ? const Color(0xFF191E00)
                      : KandoColors.mutedText,
                ),
              ),
            ),
          ),
      ],
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
        : marketChangeTextColor(change);
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
  const _ShopTile({required this.row, required this.imageUrl, this.onTap});

  final CardSoldListingRow row;
  final String? imageUrl;
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
                key: Key('card-detail-shop-image-${row.dateText}-${row.title}'),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: KandoColors.elevatedSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: KandoCardImage(imageUrl: imageUrl),
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

const _kPriceChartColors = [
  KandoColors.accent,
  Color(0xFF53D8C4),
  Color(0xFFFFB15A),
  Color(0xFFC6A7FF),
  Color(0xFF7DCB72),
  Color(0xFFE782A9),
];

class _DetailChartSeries {
  const _DetailChartSeries({
    required this.label,
    required this.points,
    required this.color,
  });

  final String label;
  final List<CardPricePoint> points;
  final Color color;
}

class _PriceChartLegend extends StatelessWidget {
  const _PriceChartLegend({required this.series});

  final List<_DetailChartSeries> series;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      children: [
        for (final item in series)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 2, color: item.color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KandoColors.mutedText,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InteractivePriceChart extends StatefulWidget {
  const _InteractivePriceChart({
    super.key,
    required this.series,
    this.quantities = const [],
    this.tooltipRows,
    this.persistentSelection = false,
    this.emphasizeSinglePoint = false,
    this.semanticKey = const Key('card-detail-price-chart-interactive'),
    this.semanticLabel = 'Card price chart',
  });

  final List<_DetailChartSeries> series;
  final List<int> quantities;
  final List<List<String>>? tooltipRows;
  final bool persistentSelection;
  final bool emphasizeSinglePoint;
  final Key semanticKey;
  final String semanticLabel;

  @override
  State<_InteractivePriceChart> createState() => _InteractivePriceChartState();
}

class _InteractivePriceChartState extends State<_InteractivePriceChart> {
  int? _selectedIndex;

  String get _semanticValue {
    if (widget.series.isEmpty) return 'No chart data';
    final selectedIndex = _selectedIndex;
    if (selectedIndex == null) return 'No chart point selected';
    final primary = widget.series.first.points;
    final index = selectedIndex.clamp(0, primary.length - 1);
    final point = primary[index];
    final rows =
        widget.tooltipRows?[index] ??
        widget.series.map((series) {
          final seriesIndex = primary.length == 1
              ? 0
              : ((index / (primary.length - 1)) * (series.points.length - 1))
                    .round();
          final label = widget.series.length == 1 ? 'Price' : series.label;
          return '$label: ${_formatDetailChartPrice(series.points[seriesIndex])}';
        }).toList();
    return [
      'Date: ${point.dateLabel}',
      ...rows,
      if (widget.tooltipRows == null && index < widget.quantities.length)
        'Qty: ${widget.quantities[index]}',
    ].join(', ');
  }

  @override
  void didUpdateWidget(covariant _InteractivePriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series != widget.series) {
      _selectedIndex = null;
    }
  }

  void _selectAt(double localX, double width) {
    final pointCount = widget.series.first.points.length;
    if (pointCount == 0 || width <= 0) return;
    if (pointCount == 1) {
      if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
      return;
    }
    final normalizedX = (localX / width).clamp(0.0, 1.0);
    final index = (normalizedX * (pointCount - 1)).round();
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  void _clearSelection() {
    if (_selectedIndex == null) return;
    setState(() => _selectedIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          key: widget.semanticKey,
          label: widget.semanticLabel,
          value: _semanticValue,
          child: MouseRegion(
            onHover: (event) => _selectAt(event.localPosition.dx, width),
            onExit: (_) {
              if (!widget.persistentSelection) _clearSelection();
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) =>
                  _selectAt(event.localPosition.dx, width),
              onPointerMove: (event) =>
                  _selectAt(event.localPosition.dx, width),
              onPointerUp: (_) {
                if (!widget.persistentSelection) _clearSelection();
              },
              onPointerCancel: (_) {
                if (!widget.persistentSelection) _clearSelection();
              },
              child: CustomPaint(
                painter: _PriceChartPainter(
                  series: widget.series,
                  quantities: widget.quantities,
                  tooltipRows: widget.tooltipRows,
                  selectedIndex: _selectedIndex,
                  emphasizeSinglePoint: widget.emphasizeSinglePoint,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  const _PriceChartPainter({
    required this.series,
    required this.quantities,
    required this.tooltipRows,
    required this.selectedIndex,
    required this.emphasizeSinglePoint,
  });

  final List<_DetailChartSeries> series;
  final List<int> quantities;
  final List<List<String>>? tooltipRows;
  final int? selectedIndex;
  final bool emphasizeSinglePoint;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var index = 1; index <= 3; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (series.isEmpty) return;
    final allValues = series
        .expand((item) => item.points)
        .map((point) => point.priceUsd)
        .whereType<double>()
        .toList();
    if (allValues.isEmpty) return;

    final minValue = allValues.reduce(math.min);
    final maxValue = allValues.reduce(math.max);
    final range = maxValue - minValue;
    const topInset = 16.0;
    const bottomInset = 12.0;
    final offsetsBySeries = <List<Offset>>[];
    for (final item in series) {
      final offsets = <Offset>[];
      for (var index = 0; index < item.points.length; index++) {
        final value = item.points[index].priceUsd;
        if (value == null) continue;
        final x = item.points.length == 1
            ? size.width / 2
            : size.width * index / (item.points.length - 1);
        final normalized = range == 0 ? 0.5 : (value - minValue) / range;
        final y =
            size.height -
            bottomInset -
            normalized * (size.height - topInset - bottomInset);
        offsets.add(Offset(x, y));
      }
      offsetsBySeries.add(offsets);
      if (offsets.length < 2) continue;
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (var index = 1; index < offsets.length; index++) {
        path.lineTo(offsets[index].dx, offsets[index].dy);
      }
      if (series.length == 1) {
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
                item.color.withValues(alpha: 0.16),
                item.color.withValues(alpha: 0),
              ],
            ).createShader(Offset.zero & size),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = item.color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    final selectedIndex = this.selectedIndex;
    if (selectedIndex == null) {
      final validPointCount = offsetsBySeries.fold<int>(
        0,
        (count, offsets) => count + offsets.length,
      );
      for (var index = 0; index < series.length; index++) {
        final offsets = offsetsBySeries[index];
        if (offsets.isNotEmpty) {
          if (emphasizeSinglePoint && validPointCount == 1) {
            canvas.drawCircle(
              offsets.single,
              6,
              Paint()..color = series[index].color.withValues(alpha: 0.2),
            );
          }
          canvas.drawCircle(
            offsets.last,
            3,
            Paint()..color = series[index].color,
          );
        }
      }
      return;
    }
    final primaryPoints = series.first.points;
    final resolvedSelectedIndex = selectedIndex.clamp(
      0,
      primaryPoints.length - 1,
    );
    final selected = primaryPoints[resolvedSelectedIndex];
    final selectedFraction = primaryPoints.length == 1
        ? 0.5
        : resolvedSelectedIndex / (primaryPoints.length - 1);
    final selectedX = size.width * selectedFraction;
    final xAxisY = size.height - bottomInset;
    _drawPriceChartDashedLine(
      canvas,
      Offset(selectedX, 0),
      Offset(selectedX, xAxisY),
      Paint()
        ..color = KandoColors.accent.withValues(alpha: 0.7)
        ..strokeWidth = 1,
    );
    final selectedPoints = <CardPricePoint>[];
    for (var index = 0; index < series.length; index++) {
      final pointIndex = (selectedFraction * (series[index].points.length - 1))
          .round();
      selectedPoints.add(series[index].points[pointIndex]);
      final offsets = offsetsBySeries[index];
      if (offsets.isEmpty) continue;
      final offsetIndex = (selectedFraction * (offsets.length - 1)).round();
      final offset = offsets[offsetIndex];
      canvas.drawCircle(
        offset,
        6,
        Paint()..color = series[index].color.withValues(alpha: 0.2),
      );
      canvas.drawCircle(offset, 3, Paint()..color = series[index].color);
    }

    final datePainter = TextPainter(
      text: TextSpan(
        text: 'Date: ${selected.dateLabel}',
        style: const TextStyle(
          color: Color(0xFF92927D),
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 16 / 11,
        ),
      ),
      maxLines: 1,
      ellipsis: '...',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0.0, size.width - 16));
    final maxTooltipRows = math.max(1, ((size.height - 28) / 14).floor());
    final customRows = tooltipRows?[resolvedSelectedIndex];
    final tooltipSeriesCount = math.min(
      customRows?.length ?? series.length,
      maxTooltipRows,
    );
    final pricePainters = [
      for (var index = 0; index < tooltipSeriesCount; index++)
        TextPainter(
          text: TextSpan(
            text:
                customRows?[index] ??
                '${series[index].label}: ${_formatDetailChartPrice(selectedPoints[index])}',
            style: TextStyle(
              color: customRows == null
                  ? series[index].color
                  : index == 0
                  ? KandoColors.accent
                  : KandoColors.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 14 / 10,
            ),
          ),
          maxLines: 1,
          ellipsis: '...',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(0.0, size.width - 16)),
      if (customRows == null && resolvedSelectedIndex < quantities.length)
        TextPainter(
          text: TextSpan(
            text: 'Qty: ${quantities[resolvedSelectedIndex]}',
            style: const TextStyle(
              color: KandoColors.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 14 / 10,
            ),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(0.0, size.width - 16)),
    ];
    final tooltipSize = Size(
      math.min(
        size.width,
        [
              datePainter.width,
              ...pricePainters.map((item) => item.width),
            ].reduce(math.max) +
            16,
      ),
      math.min(size.height, 28 + pricePainters.length * 14),
    );
    final preferredLeft = selectedX + tooltipSize.width + 12 <= size.width
        ? selectedX + 12
        : selectedX - tooltipSize.width - 12;
    final tooltipLeft = preferredLeft
        .clamp(0.0, size.width - tooltipSize.width)
        .toDouble();
    const preferredTop = 4.0;
    final tooltipTop = preferredTop
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
    for (var index = 0; index < pricePainters.length; index++) {
      pricePainters[index].paint(
        canvas,
        tooltipRect.topLeft + Offset(8, 24 + index * 14),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PriceChartPainter oldDelegate) {
    return oldDelegate.series != series ||
        oldDelegate.quantities != quantities ||
        oldDelegate.tooltipRows != tooltipRows ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.emphasizeSinglePoint != emphasizeSinglePoint;
  }
}

void _drawPriceChartDashedLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Paint paint, {
  double dash = 4,
  double gap = 4,
}) {
  final distance = (end - start).distance;
  if (distance <= 0) return;
  final direction = (end - start) / distance;
  var traveled = 0.0;
  while (traveled < distance) {
    final segmentStart = start + direction * traveled;
    final segmentEnd = start + direction * math.min(traveled + dash, distance);
    canvas.drawLine(segmentStart, segmentEnd, paint);
    traveled += dash + gap;
  }
}

String _formatDetailChartPrice(CardPricePoint point) {
  final value = point.priceUsd;
  if (value == null) return '--';
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '\$$whole.${parts.last}';
}

Future<bool?> _confirmRemoveWishlist(
  BuildContext context,
  CardDetailController controller,
) {
  _trackFromContext(context, AnalyticsEvent.deleteClick);
  return _showRemoveConfirmationSheet(
    context: context,
    title: 'This card will be removed from your wishlist',
    onRemove: controller.toggleWishlist,
  );
}

Future<bool?> _confirmRemoveCollectionItem(
  BuildContext context,
  CardDetailController controller,
  String itemId,
) {
  _trackFromContext(context, AnalyticsEvent.deleteClick);
  return _showRemoveConfirmationSheet(
    context: context,
    title: 'This card will be removed from your portfolio',
    onRemove: () => controller.removeCollectionItem(itemId),
  );
}

Future<bool?> _showRemoveConfirmationSheet({
  required BuildContext context,
  required String title,
  required Future<void> Function() onRemove,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (sheetContext) => _RemoveConfirmationSheet(
      title: title,
      onCancel: () {
        _trackFromContext(sheetContext, AnalyticsEvent.cancelClick);
        Navigator.of(sheetContext).pop(false);
      },
      onRemove: () async {
        _trackFromContext(sheetContext, AnalyticsEvent.deleteConfirmClick);
        try {
          await onRemove();
        } catch (_) {
          if (sheetContext.mounted) {
            showKandoTopFailureToast(sheetContext);
          }
          return;
        }
        if (sheetContext.mounted) {
          Navigator.of(sheetContext).pop(true);
        }
      },
    ),
  );
}

class _RemoveConfirmationSheet extends StatelessWidget {
  const _RemoveConfirmationSheet({
    required this.title,
    required this.onCancel,
    required this.onRemove,
  });

  final String title;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('card-detail-remove-confirmation-sheet'),
      color: const Color(0xFF222222),
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                child: Container(
                  width: 48,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0x66474836),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFE4E3D3),
                  fontFamily: 'Fraunces',
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  height: 32 / 24,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: _RemoveConfirmationButton(
                      key: const Key('card-detail-remove-confirmation-cancel'),
                      label: 'CANCEL',
                      backgroundColor: const Color(0xFF2A2B20),
                      foregroundColor: const Color(0xFFE4E3D3),
                      onPressed: onCancel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RemoveConfirmationButton(
                      key: const Key('card-detail-remove-confirmation-submit'),
                      label: 'REMOVE',
                      backgroundColor: const Color(0xFFF0FE6F),
                      foregroundColor: const Color(0xFF2C3400),
                      onPressed: onRemove,
                    ),
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

class _RemoveConfirmationButton extends StatelessWidget {
  const _RemoveConfirmationButton({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          side: const BorderSide(color: Color(0x14FFFFFF)),
          padding: EdgeInsets.zero,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 24 / 16,
            letterSpacing: 0,
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

void _trackFromContext(BuildContext context, String event) {
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(analyticsProvider).track(event);
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
