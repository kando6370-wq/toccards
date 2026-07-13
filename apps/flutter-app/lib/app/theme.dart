import 'package:flutter/material.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

ThemeData buildKandoTheme() {
  final colorScheme = buildKandoColorScheme();

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: KandoColors.ink,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
  );
}
