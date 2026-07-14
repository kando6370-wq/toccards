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

class _FigmaTabBar extends StatelessWidget {
  const _FigmaTabBar({required this.currentTab, required this.onSelected});

  final KandoMainTab currentTab;
  final ValueChanged<KandoMainTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        bottomInset > 32 ? bottomInset : 32,
      ),
      child: SizedBox(
        key: const Key('kando-tab-bar'),
        width: 350,
        height: 62,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
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
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    _FigmaTabItem(
                      key: const Key('kando-tab-home'),
                      label: 'Home',
                      iconAsset: 'assets/navigation/home_off.svg',
                      selectedIconAsset: 'assets/navigation/home_on.svg',
                      selected: currentTab == KandoMainTab.home,
                      onTap: () => onSelected(KandoMainTab.home),
                    ),
                    _FigmaTabItem(
                      key: const Key('kando-tab-search'),
                      label: 'Search',
                      iconAsset: 'assets/navigation/search_off.svg',
                      selectedIconAsset: 'assets/navigation/search_on.svg',
                      selected: currentTab == KandoMainTab.search,
                      onTap: () => onSelected(KandoMainTab.search),
                    ),
                    const SizedBox(width: 64),
                    _FigmaTabItem(
                      key: const Key('kando-tab-collection'),
                      label: 'collection',
                      iconAsset: 'assets/navigation/collection_off.svg',
                      selectedIconAsset: 'assets/navigation/collection_on.svg',
                      selected: currentTab == KandoMainTab.collection,
                      onTap: () => onSelected(KandoMainTab.collection),
                    ),
                    _FigmaTabItem(
                      key: const Key('kando-tab-profile'),
                      label: 'Profile',
                      iconAsset: 'assets/navigation/profile_off.svg',
                      selectedIconAsset: 'assets/navigation/profile_on.svg',
                      selected: currentTab == KandoMainTab.profile,
                      onTap: () => onSelected(KandoMainTab.profile),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 143,
              top: -21,
              child: Semantics(
                button: true,
                label: 'Scan',
                child: GestureDetector(
                  key: const Key('kando-tab-scan'),
                  onTap: () => onSelected(KandoMainTab.scan),
                  child: Container(
                    width: 64,
                    height: 64,
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
          ],
        ),
      ),
    );
  }
}

class _FigmaTabItem extends StatelessWidget {
  const _FigmaTabItem({
    super.key,
    required this.label,
    required this.iconAsset,
    required this.selectedIconAsset,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String iconAsset;
  final String selectedIconAsset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? KandoColors.accent : KandoColors.mutedText;

    return SizedBox(
      width: 69.5,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(27),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: selected
                ? BoxDecoration(
                    color: const Color(0x1FFFFFFF),
                    borderRadius: BorderRadius.circular(27),
                  )
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  selected ? selectedIconAsset : iconAsset,
                  width: 24,
                  height: 24,
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
                        fontFamily: 'Geist',
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
    KandoMainTab.home => '/',
    KandoMainTab.collection => '/collection',
    KandoMainTab.scan => '/scan',
    KandoMainTab.search => '/search',
    KandoMainTab.profile => '/profile',
  };
}
