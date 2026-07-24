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
  static const money = Color(0xFFFFF6AF);
  static const gain = Color(0xFF4ADE80);
  static const error = Color(0xFFFFB1B1);
  static const errorText = Color(0xFFFF8989);
  static const primaryOnDefault = Color(0xFF2C3400);
  static const disabledText = Color(0xFF615D3B);
  static const borderFocus = Color(0x99F0FE6F);
  static const accentGlow10 = Color(0x1AF0FE6F);
  static const borderSubtle = Color(0x14FFFFFF);
}

abstract final class KandoLayout {
  static const mainTabTopPadding = 8.0;
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
