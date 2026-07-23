import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'kando_style.dart';

enum KandoMainTab { home, collection, scan, search, profile }

class KandoTabScaffold extends StatelessWidget {
  const KandoTabScaffold({
    super.key,
    required this.currentTab,
    required this.body,
  });

  final KandoMainTab currentTab;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _tabTheme(context),
      child: Scaffold(
        extendBody: true,
        backgroundColor: KandoColors.ink,
        body: body,
        bottomNavigationBar: _FigmaTabBar(
          currentTab: currentTab,
          onSelected: (next) {
            if (next != currentTab) {
              context.go(_pathForTab(next));
            }
          },
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

class _FigmaTabBar extends StatefulWidget {
  const _FigmaTabBar({required this.currentTab, required this.onSelected});

  final KandoMainTab currentTab;
  final ValueChanged<KandoMainTab> onSelected;

  @override
  State<_FigmaTabBar> createState() => _FigmaTabBarState();
}

class _FigmaTabBarState extends State<_FigmaTabBar> {
  static const double _barWidth = 350;
  static const double _barHeight = 62;
  static const double _tabHorizontalInset = 2;
  static const double _scanButtonSize = 64;
  static const double _scanButtonTop = -21;
  static const double _bottomOffset = 10;
  static const double _highlightHeight = 54;
  static const Duration _highlightDuration = Duration(milliseconds: 220);

  static KandoMainTab? _pendingHighlightOrigin;

  late KandoMainTab _highlightedTab;

  @override
  void initState() {
    super.initState();
    _highlightedTab = _pendingHighlightOrigin ?? widget.currentTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_highlightedTab != widget.currentTab) {
        setState(() {
          _highlightedTab = widget.currentTab;
        });
      }
      _pendingHighlightOrigin = null;
    });
  }

  @override
  void didUpdateWidget(covariant _FigmaTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTab != widget.currentTab) {
      setState(() {
        _highlightedTab = widget.currentTab;
      });
      _pendingHighlightOrigin = null;
    }
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
            final highlightLeft = _highlightLeftFor(_highlightedTab, barWidth);
            final highlightWidth = _highlightWidthFor(barWidth);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(31),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0x3310100B),
                            border: Border.all(color: const Color(0x1FFFFFFF)),
                            borderRadius: BorderRadius.circular(31),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0x1FFFFFFF),
                        borderRadius: BorderRadius.all(Radius.circular(31)),
                      ),
                    ),
                  ),
                ),
                if (highlightLeft != null)
                  AnimatedPositioned(
                    key: const Key('kando-tab-selected-background'),
                    duration: _highlightDuration,
                    curve: Curves.easeOutCubic,
                    left: highlightLeft,
                    top: (_barHeight - _highlightHeight) / 2,
                    width: highlightWidth,
                    height: _highlightHeight,
                    child: const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x1FFFFFFF),
                          borderRadius: BorderRadius.all(Radius.circular(27)),
                        ),
                      ),
                    ),
                  ),
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
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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

  double? _highlightLeftFor(KandoMainTab tab, double barWidth) {
    final center = _tabCenterFor(tab, barWidth);
    if (center == null) return null;
    return center - (_highlightWidthFor(barWidth) / 2);
  }

  double? _tabCenterFor(KandoMainTab tab, double barWidth) {
    final sideGroupWidth = (barWidth - _scanButtonSize) / 2;
    final tabWidth = _tabWidthFor(barWidth);

    return switch (tab) {
      KandoMainTab.home => tabWidth / 2,
      KandoMainTab.search => tabWidth + (tabWidth / 2),
      KandoMainTab.collection =>
        sideGroupWidth + _scanButtonSize + (tabWidth / 2),
      KandoMainTab.profile =>
        sideGroupWidth + _scanButtonSize + tabWidth + (tabWidth / 2),
      KandoMainTab.scan => null,
    };
  }

  double _tabWidthFor(double barWidth) {
    return ((barWidth - _scanButtonSize) / 2) / 2;
  }

  void _selectTab(KandoMainTab next) {
    if (next != widget.currentTab) {
      _pendingHighlightOrigin = widget.currentTab;
    }
    widget.onSelected(next);
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
  });

  final double horizontalInset;
  final String label;
  final String iconAsset;
  final String selectedIconAsset;
  final bool selected;
  final VoidCallback onTap;

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
