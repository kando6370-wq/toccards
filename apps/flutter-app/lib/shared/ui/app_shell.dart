import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kando_app/shared/portfolio/pending_collection.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'kando_liquid_glass.dart';
import 'kando_style.dart';
import 'toast.dart';

enum KandoMainTab { home, collection, scan, search, profile }

class KandoTabScaffold extends ConsumerWidget {
  const KandoTabScaffold({
    super.key,
    required this.currentTab,
    required this.body,
    this.onPendingCollectionReview,
  });

  final KandoMainTab currentTab;
  final Widget body;
  final Future<int?> Function()? onPendingCollectionReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final tabBarBottomPadding =
        (bottomInset > 32 ? bottomInset : 32) - _FigmaTabBarState._bottomOffset;
    final pendingCount = ref.watch(
      pendingCollectionProvider.select((items) => items.length),
    );
    final showPendingNotice =
        currentTab != KandoMainTab.scan && pendingCount > 0;
    void selectTab(KandoMainTab next) {
      if (next != currentTab) {
        context.go(_pathForTab(next));
      }
    }

    return Theme(
      data: _tabTheme(context),
      child: Scaffold(
        extendBody: true,
        backgroundColor: KandoColors.ink,
        body: Stack(
          children: [
            Positioned.fill(child: body),
            if (showPendingNotice)
              Positioned(
                left: 20,
                right: 20,
                bottom: 96 + MediaQuery.paddingOf(context).bottom,
                child: PendingCollectionNotice(
                  count: pendingCount,
                  onReview: onPendingCollectionReview,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: tabBarBottomPadding + _FigmaTabBarState._barHeight,
              height: -_FigmaTabBarState._scanButtonTop,
              child: Center(
                child: GestureDetector(
                  key: const Key('kando-tab-scan-overflow-hit-region'),
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: () => selectTab(KandoMainTab.scan),
                  child: const SizedBox(
                    width: _FigmaTabBarState._scanButtonSize,
                    height: -_FigmaTabBarState._scanButtonTop,
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _FigmaTabBar(
          currentTab: currentTab,
          onSelected: selectTab,
        ),
      ),
    );
  }

  ThemeData _tabTheme(BuildContext context) {
    final base = Theme.of(context);
    final colorScheme = buildKandoColorScheme();
    final textTheme = base.textTheme.apply(
      bodyColor: KandoColors.text,
      displayColor: KandoColors.text,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: KandoColors.ink,
      textTheme: textTheme,
      cardTheme: const CardThemeData(
        color: KandoColors.surface,
        elevation: 0,
        margin: EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: KandoColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KandoColors.surface,
        hintStyle: const TextStyle(color: KandoColors.mutedText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: KandoColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: KandoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: KandoColors.accent, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(color: KandoColors.border),
    );
  }
}

class PendingCollectionNotice extends StatelessWidget {
  const PendingCollectionNotice({
    super.key,
    required this.count,
    this.onReview,
  });

  final int count;
  final Future<int?> Function()? onReview;

  @override
  Widget build(BuildContext context) {
    final singular = count == 1;
    return Material(
      key: const Key('pending-collection-notice'),
      color: const Color(0xF7393C21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF55582D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final addedCount = onReview == null
              ? await context.push<int>('/collection-items/pending')
              : await onReview!();
          if (context.mounted && addedCount != null && addedCount > 0) {
            showKandoCenteredSuccessToast(
              context,
              message: portfolioCardsAddedToastText(addedCount),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: KandoColors.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SvgPicture.asset(
                  'assets/search/collection_on.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    KandoColors.ink,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count ${singular ? 'card' : 'cards'} waiting for details',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KandoColors.text,
                        fontSize: 15,
                        height: 20 / 15,
                      ),
                    ),
                    Text(
                      'Tap to Review and edit ${singular ? 'it' : 'them'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KandoColors.text,
                        fontSize: 12,
                        height: 16 / 12,
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

class _FigmaTabBar extends StatefulWidget {
  const _FigmaTabBar({required this.currentTab, required this.onSelected});

  final KandoMainTab currentTab;
  final ValueChanged<KandoMainTab> onSelected;

  @override
  State<_FigmaTabBar> createState() => _FigmaTabBarState();
}

class _FigmaTabBarState extends State<_FigmaTabBar>
    with TickerProviderStateMixin {
  static const double _barWidth = 350;
  static const double _barHeight = 62;
  static const double _tabHorizontalInset = 2;
  static const double _scanButtonSize = 64;
  static const double _scanButtonTop = -21;
  static const double _bottomOffset = 10;
  static const double _highlightHeight = 54;
  static ({double position, double velocity, double activity})?
  _pendingHighlight;

  late final SingleSpringController _position;
  late final SingleSpringController _activity;
  Timer? _settleTimer;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    final pending = _pendingHighlight;
    _pendingHighlight = null;
    _position = SingleSpringController(
      vsync: this,
      spring: GlassSpring.snappy(
        duration: const Duration(milliseconds: 380),
        extraBounce: -0.03,
      ),
      initialValue: pending?.position ?? _positionForTab(widget.currentTab),
      lowerBound: 0,
      upperBound: 3,
    );
    _activity = SingleSpringController(
      vsync: this,
      spring: GlassSpring.interactive(
        duration: const Duration(milliseconds: 220),
      ),
      initialValue: pending?.activity ?? 0,
      lowerBound: 0,
      upperBound: 1,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || pending == null) return;
      _animateSelection(fromVelocity: pending.velocity);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations) {
      _settleTimer?.cancel();
      _position.setValue(_positionForTab(widget.currentTab));
      _activity.setValue(0);
    }
  }

  @override
  void didUpdateWidget(covariant _FigmaTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTab != widget.currentTab) {
      _pendingHighlight = null;
      _animateSelection();
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _position.dispose();
    _activity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        (bottomInset > 32 ? bottomInset : 32) - _bottomOffset,
      ),
      child: SizedBox(
        key: const Key('kando-tab-bar'),
        width: _barWidth,
        height: _barHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: GlassContainer(
                      key: const Key('kando-tab-liquid-glass'),
                      useOwnLayer: true,
                      quality: kandoLiquidGlassQuality,
                      clipBehavior: Clip.antiAlias,
                      shape: const LiquidRoundedSuperellipse(
                        borderRadius: 31,
                        side: BorderSide(color: Color(0x33FFFFFF)),
                      ),
                      settings: const LiquidGlassSettings(
                        bodyMode: GlassBodyMode.clear,
                        glassColor: Color(0x0FFFFFFF),
                        thickness: 26,
                        blur: 3,
                        chromaticAberration: 0.01,
                        lightIntensity: 0.6,
                        ambientStrength: 0.12,
                        refractiveIndex: 1.59,
                        saturation: 1.15,
                        glowIntensity: 0.85,
                        shadow: [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 18,
                            offset: Offset(0, 7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.currentTab != KandoMainTab.scan)
                  _buildIndicator(barWidth, glass: false),
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _FigmaTabItem(
                                key: const Key('kando-tab-home'),
                                horizontalInset: _tabHorizontalInset,
                                label: 'Home',
                                iconAsset: 'assets/navigation/home_off.svg',
                                selectedIconAsset:
                                    'assets/navigation/home_on.svg',
                                selected:
                                    widget.currentTab == KandoMainTab.home,
                                onTap: () => _selectTab(KandoMainTab.home),
                                onPressStart: () =>
                                    _previewTab(KandoMainTab.home),
                                onPressEnd: _endPress,
                                onPressCancel: _cancelPress,
                              ),
                            ),
                            Expanded(
                              child: _FigmaTabItem(
                                key: const Key('kando-tab-search'),
                                horizontalInset: _tabHorizontalInset,
                                label: 'Search',
                                iconAsset: 'assets/navigation/search_off.svg',
                                selectedIconAsset:
                                    'assets/navigation/search_on.svg',
                                selected:
                                    widget.currentTab == KandoMainTab.search,
                                onTap: () => _selectTab(KandoMainTab.search),
                                onPressStart: () =>
                                    _previewTab(KandoMainTab.search),
                                onPressEnd: _endPress,
                                onPressCancel: _cancelPress,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: _scanButtonSize),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _FigmaTabItem(
                                key: const Key('kando-tab-collection'),
                                horizontalInset: _tabHorizontalInset,
                                label: 'Collection',
                                iconAsset:
                                    'assets/navigation/collection_off.svg',
                                selectedIconAsset:
                                    'assets/navigation/collection_on.svg',
                                selected:
                                    widget.currentTab ==
                                    KandoMainTab.collection,
                                onTap: () =>
                                    _selectTab(KandoMainTab.collection),
                                onPressStart: () =>
                                    _previewTab(KandoMainTab.collection),
                                onPressEnd: _endPress,
                                onPressCancel: _cancelPress,
                              ),
                            ),
                            Expanded(
                              child: _FigmaTabItem(
                                key: const Key('kando-tab-profile'),
                                horizontalInset: _tabHorizontalInset,
                                label: 'Profile',
                                iconAsset: 'assets/navigation/profile_off.svg',
                                selectedIconAsset:
                                    'assets/navigation/profile_on.svg',
                                selected:
                                    widget.currentTab == KandoMainTab.profile,
                                onTap: () => _selectTab(KandoMainTab.profile),
                                onPressStart: () =>
                                    _previewTab(KandoMainTab.profile),
                                onPressEnd: _endPress,
                                onPressCancel: _cancelPress,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Paint the moving lens above the icons so it refracts them.
                if (widget.currentTab != KandoMainTab.scan)
                  _buildIndicator(barWidth, glass: true),
                Positioned(
                  top: _scanButtonTop,
                  left: 0,
                  right: 0,
                  child: Semantics(
                    button: true,
                    label: 'Scan',
                    child: Center(
                      child: GestureDetector(
                        key: const Key('kando-tab-scan'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selectTab(KandoMainTab.scan),
                        child: Container(
                          width: _scanButtonSize,
                          height: _scanButtonSize,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFBBFF6F), Color(0xFFF5E650)],
                            ),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: SvgPicture.asset(
                                'assets/navigation/identify.svg',
                              ),
                            ),
                          ),
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
    );
  }

  double _highlightWidthFor(double barWidth) {
    return _tabWidthFor(barWidth) - (_tabHorizontalInset * 2);
  }

  Widget _buildIndicator(double barWidth, {required bool glass}) {
    return ListenableBuilder(
      listenable: Listenable.merge([_position, _activity]),
      builder: (context, child) => Positioned(
        key: glass ? null : const Key('kando-tab-selected-background'),
        left: _highlightLeftForPosition(_position.value, barWidth),
        top: (_barHeight - _highlightHeight) / 2,
        width: _highlightWidthFor(barWidth),
        height: _highlightHeight,
        child: IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedGlassIndicator(
                key: glass
                    ? const Key('kando-tab-selected-liquid-glass')
                    : const Key('kando-tab-selected-resting-glass'),
                velocity: _position.velocity * 2 / 3,
                itemCount: 1,
                alignment: Alignment.center,
                thickness: _activity.value,
                quality: kandoLiquidGlassQuality,
                indicatorColor: const Color(0x14FFFFFF),
                isBackgroundIndicator: !glass,
                paintBackground: !glass,
                paintGlass: glass,
                expansion: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
                pinchStrength: 0.4,
                settings: const LiquidGlassSettings(
                  bodyMode: GlassBodyMode.clear,
                  glassColor: Colors.transparent,
                  thickness: 20,
                  blur: 0,
                  refractiveIndex: 1.10,
                  chromaticAberration: 0,
                  lightIntensity: 0.8,
                  ambientStrength: 0.12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _highlightLeftForPosition(double position, double barWidth) {
    final tabWidth = _tabWidthFor(barWidth);
    // The two side groups have a wider gap for the central Scan button.
    final center = switch (position) {
      <= 1 => tabWidth / 2 + position * tabWidth,
      >= 2 => barWidth - tabWidth / 2 + (position - 3) * tabWidth,
      _ => tabWidth * 1.5 + (position - 1) * (tabWidth + _scanButtonSize),
    };
    return center - _highlightWidthFor(barWidth) / 2;
  }

  double _positionForTab(KandoMainTab tab) {
    return switch (tab) {
      KandoMainTab.home => 0,
      KandoMainTab.search => 1,
      KandoMainTab.collection => 2,
      KandoMainTab.profile => 3,
      KandoMainTab.scan => 1.5,
    };
  }

  double _tabWidthFor(double barWidth) {
    return ((barWidth - _scanButtonSize) / 2) / 2;
  }

  void _selectTab(KandoMainTab next) {
    _endPress();
    if (next != widget.currentTab && next != KandoMainTab.scan) {
      // Carry the live position across GoRouter page replacement, including
      // rapid taps before the previous spring has reached its target.
      _pendingHighlight = (
        position: _position.value,
        velocity: _position.velocity,
        activity: _activity.value,
      );
    } else {
      _pendingHighlight = null;
    }
    widget.onSelected(next);
  }

  void _animateSelection({double? fromVelocity}) {
    if (_disableAnimations) {
      _position.setValue(_positionForTab(widget.currentTab));
      _activity.setValue(0);
      return;
    }
    _position.animateTo(
      _positionForTab(widget.currentTab),
      fromVelocity: fromVelocity,
    );
    _beginPress();
    _endPress();
  }

  void _beginPress() {
    _settleTimer?.cancel();
    if (!_disableAnimations) _activity.animateTo(1);
  }

  void _previewTab(KandoMainTab tab) {
    if (_disableAnimations) return;
    _position.animateTo(_positionForTab(tab));
    _beginPress();
  }

  void _cancelPress() {
    if (!_disableAnimations) {
      _position.animateTo(_positionForTab(widget.currentTab));
    }
    _endPress();
  }

  void _endPress() {
    _settleTimer?.cancel();
    if (_disableAnimations) return;
    _settleTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _activity.animateTo(0);
    });
  }
}

class _FigmaTabItem extends StatelessWidget {
  const _FigmaTabItem({
    super.key,
    required this.horizontalInset,
    required this.label,
    required this.iconAsset,
    required this.selectedIconAsset,
    required this.selected,
    required this.onTap,
    required this.onPressStart,
    required this.onPressEnd,
    required this.onPressCancel,
  });

  final double horizontalInset;
  final String label;
  final String iconAsset;
  final String selectedIconAsset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final VoidCallback onPressCancel;

  static const double _iconSize = 22;

  @override
  Widget build(BuildContext context) {
    final color = selected ? KandoColors.accent : KandoColors.mutedText;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        onTapDown: (_) => onPressStart(),
        onTapUp: (_) => onPressEnd(),
        onTapCancel: onPressCancel,
        borderRadius: BorderRadius.circular(27),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalInset),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  selected ? selectedIconAsset : iconAsset,
                  width: _iconSize,
                  height: _iconSize,
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 65,
                  height: 18,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        height: 18 / 11,
                      ),
                    ),
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

String _pathForTab(KandoMainTab tab) {
  return switch (tab) {
    KandoMainTab.home => '/home',
    KandoMainTab.collection => '/collection',
    KandoMainTab.scan => '/scan',
    KandoMainTab.search => '/search',
    KandoMainTab.profile => '/profile',
  };
}
