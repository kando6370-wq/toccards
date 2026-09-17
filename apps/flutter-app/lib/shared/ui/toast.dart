import 'dart:async';

import 'package:flutter/material.dart';

import 'kando_style.dart';

const genericFailureToastText = 'Something went wrong. Please try again.';
const networkFailureToastText =
    'No internet connection. Please check your network and try again.';
const kandoTopToastDuration = Duration(seconds: 3);
const kandoTopToastTopGap = 28.0;

OverlayEntry? _kandoTopToastEntry;
Timer? _kandoTopToastTimer;

enum KandoTopToastType { failure, network, success, warning, info }

/// Displays a non-blocking message below the top safe area. A new message
/// replaces the previous one, and can be dismissed by closing or swiping up.
void showKandoTopToast(
  BuildContext context, {
  required String message,
  KandoTopToastType type = KandoTopToastType.info,
  Duration duration = kandoTopToastDuration,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _removeKandoTopToast();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      final top = MediaQuery.paddingOf(context).top + kandoTopToastTopGap;
      return Positioned(
        left: 20,
        right: 20,
        top: top,
        child: IgnorePointer(
          ignoring: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: KandoTopToast(
              message: message,
              type: type,
              onClose: _removeKandoTopToast,
            ),
          ),
        ),
      );
    },
  );

  _kandoTopToastEntry = entry;
  overlay.insert(entry);
  _kandoTopToastTimer = Timer(duration, _removeKandoTopToast);
}

void showKandoTopFailureToast(BuildContext context) {
  showKandoTopToast(
    context,
    message: genericFailureToastText,
    type: KandoTopToastType.failure,
  );
}

void showKandoTopNetworkToast(BuildContext context) {
  showKandoTopToast(
    context,
    message: networkFailureToastText,
    type: KandoTopToastType.network,
  );
}

void _removeKandoTopToast() {
  _kandoTopToastTimer?.cancel();
  _kandoTopToastTimer = null;
  _kandoTopToastEntry?.remove();
  _kandoTopToastEntry = null;
}

class KandoTopToast extends StatelessWidget {
  const KandoTopToast({
    super.key,
    required this.message,
    this.type = KandoTopToastType.info,
    this.onClose,
  });

  final String message;
  final KandoTopToastType type;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final style = _KandoTopToastStyle.fromType(type);
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity;
          if (velocity != null && velocity < -120) {
            onClose?.call();
          }
        },
        child: Container(
          key: const Key('kando-top-toast'),
          width: 350,
          height: 74,
          decoration: BoxDecoration(
            color: KandoColors.surface,
            border: Border.all(color: KandoColors.borderSubtle),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 17),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, size: 20, color: style.iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KandoColors.text,
                    fontSize: 13,
                    height: 20 / 13,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                height: 40,
                child: IconButton(
                  tooltip: 'Close',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close,
                    size: 12,
                    color: KandoColors.mutedText,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _KandoTopToastStyle {
  const _KandoTopToastStyle({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;

  factory _KandoTopToastStyle.fromType(KandoTopToastType type) {
    return switch (type) {
      KandoTopToastType.failure => const _KandoTopToastStyle(
        icon: Icons.priority_high_rounded,
        iconColor: KandoColors.errorText,
        iconBackground: Color(0x33FF8989),
      ),
      KandoTopToastType.network => const _KandoTopToastStyle(
        icon: Icons.wifi_off_rounded,
        iconColor: KandoColors.mutedText,
        iconBackground: Color(0x1FFFFFFF),
      ),
      KandoTopToastType.success => const _KandoTopToastStyle(
        icon: Icons.check_rounded,
        iconColor: KandoColors.gain,
        iconBackground: Color(0x334ADE80),
      ),
      KandoTopToastType.warning => const _KandoTopToastStyle(
        icon: Icons.priority_high_rounded,
        iconColor: KandoColors.money,
        iconBackground: Color(0x33FFF6AF),
      ),
      KandoTopToastType.info => const _KandoTopToastStyle(
        icon: Icons.info_outline_rounded,
        iconColor: KandoColors.accent,
        iconBackground: KandoColors.accentGlow10,
      ),
    };
  }
}
