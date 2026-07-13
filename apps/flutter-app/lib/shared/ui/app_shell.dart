import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentTab.index,
          onDestinationSelected: (index) {
            final next = KandoMainTab.values[index];
            if (next == currentTab) {
              return;
            }
            context.go(_pathForTab(next));
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined),
              selectedIcon: Icon(Icons.collections_bookmark),
              label: 'Collection',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_outlined),
              selectedIcon: Icon(Icons.qr_code_scanner),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Search',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: KandoColors.surface,
        indicatorColor: KandoColors.accent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? KandoColors.accent : KandoColors.mutedText,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? KandoColors.ink : KandoColors.mutedText,
            size: 22,
          );
        }),
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

String _pathForTab(KandoMainTab tab) {
  return switch (tab) {
    KandoMainTab.home => '/',
    KandoMainTab.collection => '/collection',
    KandoMainTab.scan => '/scan',
    KandoMainTab.search => '/search',
    KandoMainTab.profile => '/profile',
  };
}
