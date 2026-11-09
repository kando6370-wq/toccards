import 'dart:ui' as ui;

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Impeller mobile builds use the full renderer. Software-rendered tests, web,
/// and older renderers use the deterministic shader-free fallback.
GlassQuality get kandoLiquidGlassQuality =>
    ui.ImageFilter.isShaderFilterSupported
    ? GlassQuality.premium
    : GlassQuality.minimal;
