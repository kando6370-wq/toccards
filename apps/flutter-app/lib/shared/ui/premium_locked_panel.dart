import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'kando_style.dart';

const _lockAsset = 'assets/home/performance_locked_lock.svg';
const _buttonLeadingAsset = 'assets/home/performance_locked_leading.svg';
const _buttonArrowAsset = 'assets/home/performance_locked_arrow.svg';

class KandoPremiumLockedPanel extends StatelessWidget {
  const KandoPremiumLockedPanel({
    super.key,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.buttonKey,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    const panelRadius = 12.0;

    return SizedBox(
      height: 427,
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(panelRadius)),
          boxShadow: [
            BoxShadow(
              color: Color(0x40000000),
              offset: Offset(0, 25),
              blurRadius: 50,
              spreadRadius: -12,
            ),
          ],
        ),
        child: ClipRRect(
          key: const Key('kando-premium-locked-panel-clip'),
          borderRadius: BorderRadius.circular(panelRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ExcludeSemantics(
                child: IgnorePointer(child: _PremiumPerformancePreview()),
              ),
              BackdropFilter(
                key: const Key('kando-premium-locked-panel-blur'),
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: CustomPaint(
                  foregroundPainter: const _GradientRRectBorderPainter(
                    radius: panelRadius,
                    strokeWidth: 1,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x1AFFFFFF), Color(0x1A9C9C58)],
                    ),
                  ),
                  child: DecoratedBox(
                    key: const Key('kando-premium-locked-panel-surface'),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x1F747B26), Color(0x0A141506)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 33,
                        top: 63,
                        right: 33,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Column(
                          key: const Key('kando-premium-locked-panel-content'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _PremiumLockIcon(),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 32,
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  title,
                                  key: const Key(
                                    'kando-premium-locked-panel-title',
                                  ),
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: KandoColors.accent,
                                    fontFamily: 'Fraunces',
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                    height: 32 / 24,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 66,
                              width: double.infinity,
                              child: Text(
                                message,
                                key: const Key(
                                  'kando-premium-locked-panel-message',
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: KandoColors.mutedText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  height: 22 / 15,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 36,
                              child: FilledButton(
                                key: buttonKey,
                                onPressed: onPressed,
                                style: FilledButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: KandoColors.accent,
                                  foregroundColor: KandoColors.primaryOnDefault,
                                  elevation: 0,
                                  shape: const StadiumBorder(),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: 173.5,
                                    child: Row(
                                      children: [
                                        SvgPicture.asset(
                                          _buttonLeadingAsset,
                                          key: const Key(
                                            'kando-premium-locked-panel-button-leading',
                                          ),
                                          width: 16,
                                          height: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            buttonLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.clip,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color:
                                                  KandoColors.primaryOnDefault,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              height: 16 / 13,
                                              letterSpacing: 0,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SvgPicture.asset(
                                          _buttonArrowAsset,
                                          key: const Key(
                                            'kando-premium-locked-panel-button-arrow',
                                          ),
                                          width: 16,
                                          height: 16,
                                        ),
                                      ],
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumPerformancePreview extends StatelessWidget {
  const _PremiumPerformancePreview();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: const Key('kando-premium-locked-panel-preview'),
      child: Column(
        children: [
          const Row(
            key: Key('kando-premium-locked-panel-preview-metrics-top'),
            children: [
              Expanded(
                child: _PreviewMetric(label: 'Total Paid', value: r'$8,240.00'),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _PreviewMetric(
                  label: 'Market Value',
                  value: r'$12,450.80',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            key: Key('kando-premium-locked-panel-preview-metrics-bottom'),
            children: [
              Expanded(
                child: _PreviewMetric(
                  label: 'Profit / Loss',
                  value: r'+$4,210.80',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _PreviewMetric(label: 'Return', value: '+51.10%'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const Key('kando-premium-locked-panel-preview-chart-panel'),
            height: 190,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: KandoColors.borderSubtle),
              color: KandoColors.ink.withValues(alpha: 0.55),
            ),
            child: const Column(
              children: [
                _PreviewRangePicker(),
                SizedBox(height: 20),
                Expanded(child: _PreviewChart()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KandoColors.borderSubtle),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF262817), Color(0xFF17180F)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: KandoColors.mutedText, fontSize: 12),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: KandoColors.accent,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRangePicker extends StatelessWidget {
  const _PreviewRangePicker();

  static const _ranges = ['1D', '7D', '15D', '1M', '3M', '1Y'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          for (final range in _ranges)
            Expanded(
              child: Center(
                child: Text(
                  range,
                  style: TextStyle(
                    color: range == '1M'
                        ? KandoColors.accent
                        : KandoColors.mutedText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewChart extends StatelessWidget {
  const _PreviewChart();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      key: Key('kando-premium-locked-panel-preview-chart'),
      painter: _PreviewChartPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _PreviewChartPainter extends CustomPainter {
  const _PreviewChartPainter();

  static const _values = <double>[
    8240,
    8710,
    8530,
    9340,
    9820,
    10420,
    10180,
    11240,
    11780,
    12450.80,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final minValue = _values.reduce(math.min);
    final maxValue = _values.reduce(math.max);
    final range = maxValue - minValue;
    const topInset = 18.0;
    const bottomInset = 6.0;
    final availableHeight = size.height - topInset - bottomInset;
    final points = <Offset>[];
    for (var index = 0; index < _values.length; index++) {
      final x = size.width * index / (_values.length - 1);
      final normalized = (_values[index] - minValue) / range;
      final y = size.height - bottomInset - normalized * availableHeight;
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final control = Offset((previous.dx + current.dx) / 2, previous.dy);
      path.quadraticBezierTo(control.dx, control.dy, current.dx, current.dy);
    }

    final areaPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KandoColors.accent.withValues(alpha: 0.2),
            KandoColors.accent.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = KandoColors.accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PremiumLockIcon extends StatelessWidget {
  const _PremiumLockIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('kando-premium-locked-panel-icon-frame'),
      width: 56,
      height: 56,
      child: CustomPaint(
        foregroundPainter: const _GradientCircleBorderPainter(),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0x1AF1FE70),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: SvgPicture.asset(
              _lockAsset,
              key: const Key('kando-premium-locked-panel-lock-icon'),
              width: 26,
              height: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientRRectBorderPainter extends CustomPainter {
  const _GradientRRectBorderPainter({
    required this.radius,
    required this.strokeWidth,
    required this.gradient,
  });

  final double radius;
  final double strokeWidth;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Offset.zero & size;
    final borderRect = rect.deflate(inset);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(borderRect, Radius.circular(radius - inset)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientRRectBorderPainter oldDelegate) {
    return radius != oldDelegate.radius ||
        strokeWidth != oldDelegate.strokeWidth ||
        gradient != oldDelegate.gradient;
  }
}

class _GradientCircleBorderPainter extends CustomPainter {
  const _GradientCircleBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 1.4;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x1AFFFFFF), Color(0x1A14150F)],
      ).createShader(rect);
    canvas.drawCircle(
      rect.center,
      (size.shortestSide - strokeWidth) / 2,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
