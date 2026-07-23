import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'kando_style.dart';

const noContentAvailableText = 'No content available';
const refreshText = 'REFRESH';

enum KandoLoadStatus { loading, content, failure }

class KandoLoadingBlock extends StatelessWidget {
  const KandoLoadingBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class KandoFailureBlock extends StatelessWidget {
  const KandoFailureBlock({required this.onRefresh, super.key});

  static const _cardWidth = 260.0;
  static const _cardHeight = 206.0;

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight.isFinite &&
              constraints.maxHeight < _cardHeight;
          final width = constraints.maxWidth.isFinite
              ? math.min(_cardWidth, constraints.maxWidth)
              : _cardWidth;

          return SizedBox(
            width: width,
            child: _FailureCard(onRefresh: onRefresh, compact: compact),
          );
        },
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.onRefresh, required this.compact});

  final VoidCallback onRefresh;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 18.0 : 33.0;
    final markSize = compact ? 40.0 : 56.0;
    final innerMarkSize = compact ? 22.0 : 28.0;
    final iconSize = compact ? 16.0 : 20.0;
    final titleGap = compact ? 4.0 : 6.0;
    final buttonGap = compact ? 10.0 : 20.0;
    final buttonHeight = compact ? 32.0 : 36.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 25,
            offset: Offset(0, 25),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x3DF0FE70),
                  Color(0x262C2D18),
                  Color(0xFF222222),
                ],
                stops: [0.0, 0.42, 1.0],
              ),
              border: Border.all(color: Color(0x33FFFFFF)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FailureRefreshMark(
                    size: markSize,
                    innerSize: innerMarkSize,
                    iconSize: iconSize,
                  ),
                  SizedBox(height: titleGap),
                  const Text(
                    noContentAvailableText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 22 / 15,
                      fontWeight: FontWeight.w400,
                      color: KandoColors.mutedText,
                    ),
                  ),
                  SizedBox(height: buttonGap),
                  SizedBox(
                    width: double.infinity,
                    height: buttonHeight,
                    child: Material(
                      color: KandoColors.accent,
                      borderRadius: BorderRadius.circular(99),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: onRefresh,
                        child: const Center(
                          child: Text(
                            refreshText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 16 / 13,
                              fontWeight: FontWeight.w400,
                              color: KandoColors.primaryOnDefault,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FailureRefreshMark extends StatelessWidget {
  const _FailureRefreshMark({
    required this.size,
    required this.innerSize,
    required this.iconSize,
  });

  final double size;
  final double innerSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Color(0x4DF0FE6F), Color(0x253A3D1F)],
        ),
      ),
      child: Center(
        child: Container(
          width: innerSize,
          height: innerSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE9FA5E),
          ),
          child: Icon(
            Icons.refresh_rounded,
            size: iconSize,
            color: KandoColors.primaryOnDefault,
          ),
        ),
      ),
    );
  }
}

class KandoEmptyBlock extends StatelessWidget {
  const KandoEmptyBlock({
    required this.title,
    this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final String title;
  final String? body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (body != null) ...[const SizedBox(height: 8), Text(body!)],
            if (primaryLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
            ],
            if (secondaryLabel != null)
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ),
      ),
    );
  }
}
