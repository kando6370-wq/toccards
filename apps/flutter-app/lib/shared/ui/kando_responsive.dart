import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Limits reading width without changing the surrounding page or its state.
class KandoContentWidth extends StatelessWidget {
  const KandoContentWidth({
    required this.child,
    this.maxWidth = 1200,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// Keeps both subtrees mounted when a window changes between one and two columns.
class KandoAdaptiveColumns extends StatelessWidget {
  const KandoAdaptiveColumns({
    required this.primary,
    required this.secondary,
    this.primaryFraction = 0.5,
    this.singleColumnMaxWidth = 672,
    this.gap = 32,
    super.key,
  });

  final Widget primary;
  final Widget secondary;
  final double primaryFraction;
  final double singleColumnMaxWidth;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final view = View.of(context);
      final keyboardInset = math.max(
        media.viewInsets.bottom,
        view.viewInsets.bottom / view.devicePixelRatio,
      );
      final availableHeight =
          media.size.height - media.padding.vertical - keyboardInset;
      final twoColumns = constraints.maxWidth >= 800 && availableHeight >= 480;
      final width = twoColumns
          ? constraints.maxWidth
          : math.min(constraints.maxWidth, singleColumnMaxWidth);
      final primaryWidth = twoColumns ? (width - gap) * primaryFraction : width;
      final secondaryWidth = twoColumns ? width - gap - primaryWidth : width;
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              SizedBox(width: primaryWidth, child: primary),
              SizedBox(width: secondaryWidth, child: secondary),
            ],
          ),
        ),
      );
    },
  );
}

SliverGridDelegateWithFixedCrossAxisCount kandoCardGridDelegate(
  BuildContext context,
  double availableWidth,
) {
  final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final widthScale = textScale.clamp(1.0, 1.5);
  final minimumCardWidth = 170 * widthScale;
  // Allow a compact pair on phones after safe areas and page padding.
  final minimumColumns = availableWidth >= 320 * widthScale ? 2 : 1;
  final columns = math.max(
    minimumColumns,
    ((availableWidth + 10) / (minimumCardWidth + 10)).floor(),
  );
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    mainAxisExtent: 378 + math.max(0, textScale - 1) * 112,
  );
}
