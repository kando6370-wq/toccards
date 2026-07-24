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
const Color _kCollectionCardStart = Color(0x1F747B26);
const Color _kCollectionCardEnd = Color(0x0A141506);
const Color _kCollectionOutline = Color(0x1A90927C);
const Color _kCollectionSecondaryText = Color(0xFF92927D);
const Color _kRemovePortfolioColor = Color(0xFFFACC15);
const List<String> _kEditGraderOptions = [
  'Raw',
  'PSA',
  'BGS',
  'TAG',
  'CGC',
  'AGS',
];
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
        child: _CardDetailKeyboardDismissOnPointerDown(
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
                    return RefreshIndicator(
                      key: const Key('card-detail-pull-to-refresh'),
                      onRefresh: controller.refresh,
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
                            onBack: () => _goBack(context),
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
                            _PrimaryActions(
                              state: state,
                              controller: controller,
                            ),
                          const SizedBox(height: 28),
                          // _BasicInfo(state: state),
                          // const SizedBox(height: 28),
                          if (state.assetStateStatus ==
                                  KandoLoadStatus.content &&
                              state.detail.isCollected)
                            _OwnedDetailTabs(
                              state: state,
                              controller: controller,
                            )
                          else
                            _PriceOverview(
                              state: state,
                              controller: controller,
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
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/search');
  }
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
                                  WebHtmlElementStrategy.prefer,
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
        LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: math.min(constraints.maxWidth, 350),
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
                  tabs: const [
                    Tab(height: 42, text: 'Collection Item'),
                    Tab(height: 42, text: 'Price'),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        if (_tabController.index == 0)
          _CollectionItems(state: widget.state, controller: widget.controller)
        else
          _PriceOverview(state: widget.state, controller: widget.controller),
      ],
    );
  }
}

enum _CollectionItemMode { empty, summary, edit }

class _CollectionItems extends StatelessWidget {
  const _CollectionItems({required this.state, required this.controller});

  static const _modeTransitionDuration = Duration(milliseconds: 380);

  final CardDetailState state;
  final CardDetailController controller;

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
              onPressed: () => _openAddCollectionItemSheet(context, controller),
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
                        controller.startEditingCollectionItem(item.id);
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
                      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
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
    super.key,
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
    final saving = state.isSavingCollectionItemDraft;
    final languageValue = cardCollectionLanguages.contains(draft.language)
        ? draft.language
        : cardCollectionLanguages.first;
    final finishValue = cardCollectionFinishes.contains(draft.finish)
        ? draft.finish
        : cardCollectionFinishes.first;
    final gradeValue = cardCollectionGradeValues.contains(draft.grade)
        ? draft.grade
        : cardCollectionGradeValues.first;
    final useEditCard = isEditing && showHeader && showActions && !embedded;

    if (useEditCard) {
      return _CollectionItemEditCard(
        state: state,
        controller: controller,
        draft: draft,
        languageValue: languageValue,
        finishValue: finishValue,
        gradeValue: gradeValue,
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
            onSelected: (value) {
              controller.updateCollectionItemDraft(grader: value);
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
          _ChoiceField(
            key: const Key('card-detail-item-language'),
            label: 'Language',
            value: languageValue,
            options: cardCollectionLanguages,
            onSelected: (value) {
              controller.updateCollectionItemDraft(language: value);
            },
          ),
          const SizedBox(height: 12),
          _ChoiceField(
            key: const Key('card-detail-item-finish'),
            label: 'Finish',
            value: finishValue,
            options: cardCollectionFinishes,
            onSelected: (value) {
              controller.updateCollectionItemDraft(finish: value);
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

class _CollectionItemEditCard extends StatelessWidget {
  const _CollectionItemEditCard({
    required this.state,
    required this.controller,
    required this.draft,
    required this.languageValue,
    required this.finishValue,
    required this.gradeValue,
  });

  final CardDetailState state;
  final CardDetailController controller;
  final CardCollectionItemDraft draft;
  final String languageValue;
  final String finishValue;
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'OWNERSHIP\nSUMMARY',
                  style: _kCollectionHeadlineStyle,
                ),
              ),
              const SizedBox(width: 12),
              _CollectionEditActionButton(
                label: 'Cancel',
                disabled: state.isSavingCollectionItemDraft,
                onPressed: controller.cancelCollectionItemEdit,
              ),
              const SizedBox(width: 8),
              _CollectionEditActionButton(
                buttonKey: const Key('card-detail-item-submit'),
                label: 'Save changes',
                accent: true,
                loading: state.isSavingCollectionItemDraft,
                onPressed: () async {
                  await controller.saveCollectionItemDraft();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
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
          _CollectionPillGroup(
            key: const Key('card-detail-item-grader'),
            label: 'GRADER',
            selected: draft.grader,
            options: _optionsWithSelected(_kEditGraderOptions, draft.grader),
            columns: 3,
            onSelected: (value) {
              controller.updateCollectionItemDraft(grader: value);
            },
          ),
          const SizedBox(height: 32),
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
            _ChoiceField(
              key: const Key('card-detail-item-grade'),
              label: 'GRADE',
              value: gradeValue,
              options: cardCollectionGradeValues,
              displayBuilder: (grade) => '${draft.grader} $grade',
              onSelected: (value) {
                controller.updateCollectionItemDraft(grade: value);
              },
            ),
          const SizedBox(height: 32),
          _ChoiceField(
            key: const Key('card-detail-item-language'),
            label: 'LANGUAGE',
            value: languageValue,
            options: cardCollectionLanguages,
            onSelected: (value) {
              controller.updateCollectionItemDraft(language: value);
            },
          ),
          const SizedBox(height: 32),
          _ChoiceField(
            key: const Key('card-detail-item-finish'),
            label: 'FINISH',
            value: finishValue,
            options: cardCollectionFinishes,
            onSelected: (value) {
              controller.updateCollectionItemDraft(finish: value);
            },
          ),
          const SizedBox(height: 32),
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
          const SizedBox(height: 28),
          const Divider(height: 1, thickness: 1, color: _kCollectionOutline),
          const SizedBox(height: 33),
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

class _CollectionEditActionButton extends StatelessWidget {
  const _CollectionEditActionButton({
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.accent = false,
    this.loading = false,
    this.disabled = false,
  });

  final Key? buttonKey;
  final String label;
  final VoidCallback onPressed;
  final bool accent;
  final bool loading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextButton(
        key: buttonKey,
        style: TextButton.styleFrom(
          backgroundColor: accent
              ? KandoColors.accent
              : KandoColors.elevatedSurface,
          foregroundColor: accent
              ? KandoColors.primaryOnDefault
              : KandoColors.text,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: const StadiumBorder(
            side: BorderSide(color: KandoColors.borderSubtle),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            height: 16 / 13,
            fontWeight: FontWeight.w400,
          ),
        ),
        onPressed: loading || disabled ? null : onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent
                      ? KandoColors.primaryOnDefault
                      : KandoColors.text,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(label),
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
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final screenHeight = MediaQuery.sizeOf(sheetContext).height;
      final maxHeight = math.min(screenHeight * 0.68, 520.0);

      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Material(
              color: const Color(0xFF191A12),
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(24),
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
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
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
        _MarketPriceCategories(
          selected: state.selectedMarketPriceCategory,
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
    required this.onSelected,
  });

  final CardMarketPriceCategory selected;
  final ValueChanged<CardMarketPriceCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 8,
      children: [
        for (final category in CardMarketPriceCategory.values)
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
                child: imageUrl == null
                    ? const Icon(
                        Icons.storefront_outlined,
                        color: KandoColors.mutedText,
                      )
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.contain,
                        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.storefront_outlined,
                              color: KandoColors.mutedText,
                            ),
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
            icon: const _RemoveActionIcon(),
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
            icon: const _RemoveActionIcon(),
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
