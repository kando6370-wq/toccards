import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'kando_style.dart';

enum KandoUpdateModalResult { updateNow, later }

/// Shows an optional or mandatory app update prompt.
/// Store launching and update policy belong to the caller.
Future<KandoUpdateModalResult?> showKandoUpdateModal(
  BuildContext context, {
  required String title,
  required String message,
  String primaryLabel = 'INSTALL',
  String secondaryLabel = 'LATER',
  bool forceUpdate = false,
}) {
  return showDialog<KandoUpdateModalResult>(
    context: context,
    barrierDismissible: !forceUpdate,
    builder: (context) {
      final modal = KandoUpdateModal(
        title: title,
        message: message,
        primaryLabel: primaryLabel,
        secondaryLabel: secondaryLabel,
        forceUpdate: forceUpdate,
        onPrimary: () =>
            Navigator.of(context).pop(KandoUpdateModalResult.updateNow),
        onSecondary: () =>
            Navigator.of(context).pop(KandoUpdateModalResult.later),
      );
      return forceUpdate ? PopScope(canPop: false, child: modal) : modal;
    },
  );
}

/// Update prompt body for callers that provide their own modal barrier.
class KandoUpdateModal extends StatelessWidget {
  const KandoUpdateModal({
    super.key,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    this.forceUpdate = false,
  });

  final String title;
  final String message;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;
  final bool forceUpdate;

  @override
  Widget build(BuildContext context) {
    return _KandoUpdateFrame(
      height: forceUpdate ? 396.267 : 452.267,
      child: Padding(
        padding: const EdgeInsets.all(33),
        child: SizedBox(
          width: 276,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      const _KandoUpdateVisual(),
                      const SizedBox(height: 30),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: KandoColors.accent,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          height: 32 / 24,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: KandoColors.mutedText,
                          fontSize: 15,
                          height: 22 / 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _KandoUpdateButton(label: primaryLabel, onPressed: onPrimary),
              if (!forceUpdate) ...[
                const SizedBox(height: 12),
                _KandoUpdateButton(
                  label: secondaryLabel,
                  secondary: true,
                  onPressed: onSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KandoUpdateFrame extends StatelessWidget {
  const _KandoUpdateFrame({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        key: const Key('kando-modal-frame'),
        width: 342,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 50,
              spreadRadius: -12,
              offset: Offset(0, 25),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: const _KandoUpdateSurfacePainter(),
          child: child,
        ),
      ),
    );
  }
}

class _KandoUpdateSurfacePainter extends CustomPainter {
  const _KandoUpdateSurfacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    // Figma 736:13370: keep the diamond falloff stable as the frame resizes.
    final transform = Matrix4.identity()
      ..setEntry(0, 0, 0.1985977590084076)
      ..setEntry(0, 1, 0.15397658944129944)
      ..setEntry(0, 3, 0.6621649861335754)
      ..setEntry(1, 0, -0.13236625492572784)
      ..setEntry(1, 1, 0.08926185220479965)
      ..setEntry(1, 3, 0.5021498203277588);
    final paint = Paint()
      ..isAntiAlias = false
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(0.25, 0.25),
        const [
          Color.from(
            alpha: 0.24,
            red: 240 / 255,
            green: 254 / 255,
            blue: 112 / 255,
          ),
          Color.from(
            alpha: 0.24,
            red: 16 / 255,
            green: 0.06143791228532791,
            blue: 11 / 255,
          ),
        ],
        const [0, 0.667445719242096],
      );
    canvas.save();
    canvas.clipRect(rect);
    canvas.scale(size.width, size.height);
    canvas.transform(Matrix4.inverted(transform).storage);
    canvas.translate(0.5, 0.5);
    for (final direction in const [
      Offset(1, 1),
      Offset(1, -1),
      Offset(-1, 1),
      Offset(-1, -1),
    ]) {
      canvas.save();
      canvas.scale(direction.dx, direction.dy);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), paint);
      canvas.restore();
    }
    canvas.restore();

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(15.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.from(alpha: 0.1, red: 1, green: 1, blue: 1),
            Color.from(
              alpha: 0.1,
              red: 0.6110798716545105,
              green: 0.6110798716545105,
              blue: 0.3442450761795044,
            ),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_KandoUpdateSurfacePainter oldDelegate) => false;
}

class _KandoUpdateButton extends StatelessWidget {
  const _KandoUpdateButton({
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: secondary
              ? KandoColors.elevatedSurface
              : KandoColors.accent,
          foregroundColor: secondary
              ? KandoColors.text
              : KandoColors.primaryOnDefault,
          shape: StadiumBorder(
            side: BorderSide(
              color: secondary ? KandoColors.borderSubtle : Colors.transparent,
            ),
          ),
          textStyle: TextStyle(
            fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
            fontSize: 13,
            height: 16 / 13,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _KandoUpdateVisual extends StatelessWidget {
  const _KandoUpdateVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('kando-update-rocket'),
      width: 160,
      height: 158.267,
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minWidth: 160,
        maxWidth: 160,
        minHeight: 165.333,
        maxHeight: 165.333,
        child: Image.asset(
          'assets/ui/update_rocket.png',
          width: 160,
          height: 165.333,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
