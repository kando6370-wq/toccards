import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'kando_style.dart';

const premiumUnlockedToastDuration = Duration(seconds: 3);
const premiumUnlockedToastTopGap = 28.0;
const premiumUnlockedToastText = 'Premium unlocked';

const _premiumUnlockedIconAsset =
    'assets/subscription/premium_unlocked_2248_18893.svg';

OverlayEntry? _premiumUnlockedToastEntry;
Timer? _premiumUnlockedToastTimer;

void showPremiumUnlockedToast(
  BuildContext context, {
  Duration duration = premiumUnlockedToastDuration,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _removePremiumUnlockedToast();

  final entry = OverlayEntry(
    builder: (context) {
      final top =
          MediaQuery.paddingOf(context).top + premiumUnlockedToastTopGap;
      return Positioned(
        left: 0,
        right: 0,
        top: top,
        child: const IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: PremiumUnlockedToast(),
          ),
        ),
      );
    },
  );

  _premiumUnlockedToastEntry = entry;
  overlay.insert(entry);
  _premiumUnlockedToastTimer = Timer(duration, _removePremiumUnlockedToast);
}

void _removePremiumUnlockedToast() {
  _premiumUnlockedToastTimer?.cancel();
  _premiumUnlockedToastTimer = null;
  final entry = _premiumUnlockedToastEntry;
  _premiumUnlockedToastEntry = null;
  entry?.remove();
}

class PremiumUnlockedToast extends StatelessWidget {
  const PremiumUnlockedToast({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: premiumUnlockedToastText,
      child: Container(
        key: const Key('premium-unlocked-toast'),
        width: 201,
        height: 48,
        decoration: const BoxDecoration(
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
          key: const Key('premium-unlocked-toast-clip'),
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            key: const Key('premium-unlocked-toast-blur'),
            filter: ui.ImageFilter.blur(sigmaX: 15.05, sigmaY: 15.05),
            child: ColoredBox(
              key: const Key('premium-unlocked-toast-surface'),
              color: const Color(0xCC4D4F36),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      _premiumUnlockedIconAsset,
                      key: const Key('premium-unlocked-toast-icon'),
                      width: 32,
                      height: 32,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        premiumUnlockedToastText,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: KandoColors.mutedText,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 20 / 14,
                          letterSpacing: 0,
                          decoration: TextDecoration.none,
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
    );
  }
}
