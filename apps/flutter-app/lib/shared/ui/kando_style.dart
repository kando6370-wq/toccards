import 'package:flutter/material.dart';

abstract final class KandoColors {
  static const ink = Color(0xFF10100B);
  static const surface = Color(0xFF1A1C14);
  static const elevatedSurface = Color(0xFF2A2B20);
  static const border = Color(0xFF464835);
  static const text = Color(0xFFEEECD8);
  static const mutedText = Color(0xFFC7C8B0);
  static const accent = Color(0xFFF0FE6F);
  static const softAccent = Color(0xFFF0E7FF);
}

ColorScheme buildKandoColorScheme() {
  return ColorScheme.fromSeed(
    seedColor: KandoColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: KandoColors.surface,
    onSurface: KandoColors.text,
    primary: KandoColors.accent,
    onPrimary: KandoColors.ink,
    secondary: KandoColors.softAccent,
    onSecondary: KandoColors.ink,
    secondaryContainer: KandoColors.elevatedSurface,
    onSecondaryContainer: KandoColors.text,
    outline: KandoColors.border,
  );
}
