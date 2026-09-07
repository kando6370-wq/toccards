import 'package:flutter/material.dart';

ThemeData buildKandoTheme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
  );
}
