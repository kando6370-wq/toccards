import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

import 'subscription_controller.dart';
import 'subscription_entitlement_cache.dart';

class PremiumPageHeader extends StatelessWidget {
  const PremiumPageHeader({
    required this.title,
    required this.source,
    super.key,
  });

  final String title;
  final String source;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: Key('$source-premium-page-header'),
      height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            key: Key('$source-premium-page-title'),
            style: const TextStyle(
              color: KandoColors.text,
              fontFamily: 'Fraunces',
              fontSize: 24,
              fontWeight: FontWeight.w600,
              height: 32 / 24,
            ),
          ),
          PremiumTopEntry(source: source, label: 'PRO'),
        ],
      ),
    );
  }
}

class PremiumTopEntry extends ConsumerWidget {
  const PremiumTopEntry({required this.source, this.label, super.key});

  final String source;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premiumState = ref.watch(
      subscriptionControllerProvider.select((state) => state.premiumState),
    );
    if (premiumState != AppPremiumState.free) {
      return const SizedBox.shrink();
    }

    void onPressed() {
      context.push(
        Uri(
          path: '/subscription',
          queryParameters: {
            'source': source,
            'entry_source': 'top_subscription_entry',
          },
        ).toString(),
      );
    }

    if (label != null) {
      return Tooltip(
        message: 'View Premium plans',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: Key('$source-premium-top-entry'),
                onTap: onPressed,
                borderRadius: BorderRadius.circular(999),
                child: Ink(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12.5),
                  decoration: BoxDecoration(
                    color: KandoColors.accentGlow10,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: KandoColors.borderFocus,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/profile/premium_crown.svg',
                        width: 16,
                        height: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label!,
                        style: const TextStyle(
                          color: KandoColors.text,
                          fontSize: 14,
                          height: 24 / 14,
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

    return Tooltip(
      message: 'View Premium plans',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('$source-premium-top-entry'),
              onTap: onPressed,
              borderRadius: BorderRadius.circular(9999),
              child: Ink(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(
                    color: KandoColors.borderFocus,
                    width: 0.5,
                  ),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/profile/premium_crown.svg',
                    width: 16,
                    height: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
