import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'kando_style.dart';

enum SubscriptionRestoreResultType { premiumRestored, notFound, failed }

const subscriptionRestoreSuccessDuration = Duration(milliseconds: 2750);
const subscriptionRestoreNotFoundDuration = Duration(milliseconds: 3500);
const subscriptionRestoreResultWidth = 260.0;

const premiumRestoredTitle = 'Premium restored';
const premiumRestoredMessage = 'Your premium access is ready to use.';
const restoreNotFoundTitle = 'No subscription found';
const restoreNotFoundMessage =
    'We couldn\u2019t find an active purchase to restore.';
const restoreFailedTitle = 'Restore failed';
const restoreFailedMessage = 'Something went wrong. Please try again later.';

const _premiumRestoredIcon =
    'assets/subscription/restore_premium_2110_4634.svg';
const _restoreNotFoundIcon =
    'assets/subscription/restore_not_found_2110_4643.svg';
const _restoreFailedIcon = 'assets/subscription/restore_failed_2110_4652.svg';

OverlayEntry? _restoreResultEntry;
Timer? _restoreResultTimer;

void showSubscriptionRestoreResult(
  BuildContext context, {
  required SubscriptionRestoreResultType type,
  Duration? duration,
}) {
  _removeSubscriptionRestoreResult();
  if (type == SubscriptionRestoreResultType.failed) {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: _SubscriptionRestoreResultViewport(
            type: type,
            onAction: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
    return;
  }

  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (context) => Positioned.fill(
      child: IgnorePointer(
        child: _SubscriptionRestoreResultViewport(type: type),
      ),
    ),
  );
  _restoreResultEntry = entry;
  overlay.insert(entry);
  _restoreResultTimer = Timer(
    duration ?? type.displayDuration,
    _removeSubscriptionRestoreResult,
  );
}

void _removeSubscriptionRestoreResult() {
  _restoreResultTimer?.cancel();
  _restoreResultTimer = null;
  final entry = _restoreResultEntry;
  _restoreResultEntry = null;
  entry?.remove();
}

extension on SubscriptionRestoreResultType {
  double get designHeight => switch (this) {
    SubscriptionRestoreResultType.premiumRestored => 204,
    SubscriptionRestoreResultType.notFound => 230,
    SubscriptionRestoreResultType.failed => 260,
  };

  Duration get displayDuration => switch (this) {
    SubscriptionRestoreResultType.premiumRestored =>
      subscriptionRestoreSuccessDuration,
    SubscriptionRestoreResultType.notFound =>
      subscriptionRestoreNotFoundDuration,
    SubscriptionRestoreResultType.failed => Duration.zero,
  };

  String get title => switch (this) {
    SubscriptionRestoreResultType.premiumRestored => premiumRestoredTitle,
    SubscriptionRestoreResultType.notFound => restoreNotFoundTitle,
    SubscriptionRestoreResultType.failed => restoreFailedTitle,
  };

  String get message => switch (this) {
    SubscriptionRestoreResultType.premiumRestored => premiumRestoredMessage,
    SubscriptionRestoreResultType.notFound => restoreNotFoundMessage,
    SubscriptionRestoreResultType.failed => restoreFailedMessage,
  };

  int get titleLines => switch (this) {
    SubscriptionRestoreResultType.premiumRestored ||
    SubscriptionRestoreResultType.failed => 1,
    SubscriptionRestoreResultType.notFound => 2,
  };
}

class _SubscriptionRestoreResultViewport extends StatelessWidget {
  const _SubscriptionRestoreResultViewport({required this.type, this.onAction});

  final SubscriptionRestoreResultType type;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.min(
              1.0,
              math.min(
                constraints.maxWidth / subscriptionRestoreResultWidth,
                constraints.maxHeight / type.designHeight,
              ),
            );
            return Center(
              child: SizedBox(
                key: Key('subscription-restore-${type.name}-frame'),
                width: subscriptionRestoreResultWidth * scale,
                height: type.designHeight * scale,
                child: OverflowBox(
                  minWidth: subscriptionRestoreResultWidth,
                  maxWidth: subscriptionRestoreResultWidth,
                  minHeight: type.designHeight,
                  maxHeight: type.designHeight,
                  child: Transform.scale(
                    scale: scale,
                    child: SubscriptionRestoreResultCard(
                      type: type,
                      onAction: onAction,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SubscriptionRestoreResultCard extends StatelessWidget {
  const SubscriptionRestoreResultCard({
    super.key,
    required this.type,
    this.onAction,
  });

  final SubscriptionRestoreResultType type;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${type.title}. ${type.message}',
      child: Container(
        key: Key('subscription-restore-${type.name}-card'),
        width: subscriptionRestoreResultWidth,
        height: type.designHeight,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Color(0x40000000),
              offset: Offset(0, 25),
              blurRadius: 25,
            ),
          ],
        ),
        child: ClipRRect(
          key: Key('subscription-restore-${type.name}-clip'),
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            key: Key('subscription-restore-${type.name}-blur'),
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: DecoratedBox(
              key: Key('subscription-restore-${type.name}-surface'),
              decoration: BoxDecoration(
                color: const Color(0xFF292B22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    key: Key('subscription-restore-${type.name}-background'),
                    painter: _SubscriptionRestoreBackgroundPainter(
                      designHeight: type.designHeight,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(33),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SubscriptionRestoreIcon(type: type),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 26.0 * type.titleLines,
                          child: Center(
                            child: Text(
                              type.title,
                              key: Key(
                                'subscription-restore-${type.name}-title',
                              ),
                              textAlign: TextAlign.center,
                              maxLines: type.titleLines,
                              overflow: TextOverflow.clip,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                color:
                                    type ==
                                        SubscriptionRestoreResultType
                                            .premiumRestored
                                    ? KandoColors.accent
                                    : KandoColors.errorText,
                                fontFamily: 'Fraunces',
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                height: 26 / 20,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 44,
                          child: Text(
                            type.message,
                            key: Key(
                              'subscription-restore-${type.name}-message',
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.clip,
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              color: KandoColors.mutedText,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              height: 22 / 15,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        if (type == SubscriptionRestoreResultType.failed) ...[
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 36,
                            child: TextButton(
                              key: const Key(
                                'subscription-restore-failed-action',
                              ),
                              onPressed: onAction,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                foregroundColor: const Color(0xFF2C3400),
                                backgroundColor: KandoColors.accent,
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  height: 16 / 13,
                                  letterSpacing: 0,
                                ),
                              ),
                              child: const Text(
                                'OK',
                                textScaler: TextScaler.noScaling,
                              ),
                            ),
                          ),
                        ],
                      ],
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

class _SubscriptionRestoreIcon extends StatelessWidget {
  const _SubscriptionRestoreIcon({required this.type});

  final SubscriptionRestoreResultType type;

  @override
  Widget build(BuildContext context) {
    if (type == SubscriptionRestoreResultType.premiumRestored) {
      return SvgPicture.asset(
        _premiumRestoredIcon,
        key: const Key('subscription-restore-premiumRestored-icon'),
        width: 56,
        height: 56,
      );
    }
    final asset = type == SubscriptionRestoreResultType.notFound
        ? _restoreNotFoundIcon
        : _restoreFailedIcon;
    return Container(
      key: Key('subscription-restore-${type.name}-icon-container'),
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x1FF87171),
        shape: BoxShape.circle,
      ),
      child: SvgPicture.asset(
        asset,
        key: Key('subscription-restore-${type.name}-icon'),
        width: 26,
        height: 26,
      ),
    );
  }
}

class _SubscriptionRestoreBackgroundPainter extends CustomPainter {
  const _SubscriptionRestoreBackgroundPainter({required this.designHeight});

  final double designHeight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF292B22),
    );
    final overlay = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(5, 5),
        const [
          Color(0x3DF0FE70),
          Color(0x3DB8C257),
          Color(0x3D9CA54A),
          Color(0x3D80873E),
          Color(0x3D646931),
          Color(0x3D484B24),
          Color(0x3D2C2D18),
          Color(0x3D1E1F11),
          Color(0x3D10100B),
        ],
        const [
          0,
          0.16686,
          0.25029,
          0.33372,
          0.41715,
          0.50058,
          0.58402,
          0.62573,
          0.66745,
        ],
      );

    canvas.save();
    canvas.scale(
      size.width / subscriptionRestoreResultWidth,
      size.height / designHeight,
    );
    canvas.transform(
      Float64List.fromList([
        30.45,
        designHeight * 0.1736716,
        0,
        0,
        -52.526,
        designHeight * 0.2605686,
        0,
        0,
        0,
        0,
        1,
        0,
        -96.5,
        -designHeight * 0.5744608,
        0,
        1,
      ]),
    );
    for (final scaleX in const [-1.0, 1.0]) {
      for (final scaleY in const [-1.0, 1.0]) {
        canvas.save();
        canvas.scale(scaleX, scaleY);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 73.758, 26.43), overlay);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SubscriptionRestoreBackgroundPainter oldDelegate) {
    return oldDelegate.designHeight != designHeight;
  }
}
