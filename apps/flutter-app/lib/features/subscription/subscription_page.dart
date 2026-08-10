import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/toast.dart';
import 'package:url_launcher/url_launcher.dart';

import '../profile/profile_actions.dart';
import 'subscription_controller.dart';

const _benefits = [
  'Unlimited Card Scanning',
  'Unlimited Portfolio Folders',
  'Use Wishlist Features',
  'Track Portfolio Performance',
  'Extended Price History',
];

class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({this.sheet = false, super.key});

  final bool sheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionControllerProvider);
    ref.listen(subscriptionControllerProvider, (previous, next) {
      if (next.isPro &&
          next.completionCount != previous?.completionCount &&
          context.mounted) {
        context.go('/subscription/success');
      }
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage &&
          context.mounted) {
        showKandoToast(context, message: next.errorMessage!);
      }
    });

    final content = Stack(
      children: [
        Positioned.fill(child: _PaywallBackground(sheet: sheet)),
        CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 98)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverList.list(
                children: [
                  const Text(
                    'Performance Pro',
                    style: TextStyle(
                      color: KandoColors.text,
                      fontFamily: 'Fraunces',
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ..._benefits.map(_BenefitRow.new),
                  const SizedBox(height: 18),
                  ...subscriptionPlans.map(
                    (plan) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PlanTile(
                        plan: plan,
                        price:
                            state.displayPrices[plan.id] ?? plan.fallbackPrice,
                        selected: state.selectedPlanId == plan.id,
                        onTap: () => ref
                            .read(subscriptionControllerProvider.notifier)
                            .selectPlan(plan.id),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      key: const Key('subscription-purchase-button'),
                      onPressed: state.isLoading
                          ? null
                          : () => ref
                                .read(subscriptionControllerProvider.notifier)
                                .purchase(),
                      style: FilledButton.styleFrom(
                        backgroundColor: KandoColors.accent,
                        foregroundColor: KandoColors.primaryOnDefault,
                        disabledBackgroundColor: KandoColors.accent.withValues(
                          alpha: 0.45,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: state.isLoading
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: KandoColors.primaryOnDefault,
                              ),
                            )
                          : const Text('SUBSCRIBE'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LegalLink(
                        label: 'Terms of Use',
                        onTap: () =>
                            ref.read(profileActionsProvider).openTerms(),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '·',
                          style: TextStyle(color: KandoColors.mutedText),
                        ),
                      ),
                      _LegalLink(
                        label: 'Privacy Policy',
                        onTap: () =>
                            ref.read(profileActionsProvider).openPrivacy(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 20,
          child: _CircleAction(
            tooltip: 'Close',
            icon: Icons.close,
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/profile'),
          ),
        ),
        Positioned(
          top: 12,
          right: 20,
          child: TextButton(
            onPressed: state.isLoading
                ? null
                : () => ref
                      .read(subscriptionControllerProvider.notifier)
                      .restore(),
            child: const Text('Restore'),
          ),
        ),
      ],
    );
    if (!sheet) {
      return Scaffold(
        backgroundColor: KandoColors.ink,
        body: SafeArea(bottom: false, child: content),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ColoredBox(
            color: KandoColors.ink,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: content,
                ),
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      key: const Key('subscription-sheet-handle'),
                      width: 48,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF615D3B),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SubscriptionSuccessPage extends StatelessWidget {
  const SubscriptionSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KandoColors.ink,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 83, 20, 32),
              child: Column(
                children: [
                  const _SuccessBadge(),
                  const SizedBox(height: 25),
                  const Text(
                    'You are Pro now',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: KandoColors.text,
                      fontFamily: 'Fraunces',
                      fontSize: 32,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Performance Pro is active on your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: KandoColors.text,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  const _SuccessBenefitRow('Unlimited Card Scanning'),
                  const SizedBox(height: 12),
                  const _SuccessBenefitRow('Unlimited Portfolio Folders'),
                  const SizedBox(height: 12),
                  const _SuccessBenefitRow('Extended Price History'),
                  const SizedBox(height: 44),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      key: const Key('subscription-success-continue'),
                      onPressed: () => context.go('/home'),
                      child: const Text('CONTINUE'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _openSubscriptionManagement(context),
                    child: const Text('Manage subscription'),
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

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('subscription-success-badge'),
      width: 128,
      height: 135,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KandoColors.accentGlow10,
              border: Border.all(color: KandoColors.accent, width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x403E4910), blurRadius: 22),
                BoxShadow(color: Color(0x332F3A00), blurRadius: 42),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 54,
              color: KandoColors.accent,
            ),
          ),
          const Positioned(
            left: -22,
            top: 5,
            child: Icon(
              Icons.auto_awesome,
              size: 14,
              color: KandoColors.accent,
            ),
          ),
          const Positioned(
            right: -18,
            top: 34,
            child: Icon(
              Icons.auto_awesome,
              size: 10,
              color: KandoColors.accent,
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: KandoColors.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  color: Color(0xFF5B6300),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessBenefitRow extends StatelessWidget {
  const _SuccessBenefitRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33D4E157)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: KandoColors.accentGlow10,
            ),
            child: const Icon(Icons.check, size: 14, color: KandoColors.accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: KandoColors.text,
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openSubscriptionManagement(BuildContext context) async {
  final uri = defaultTargetPlatform == TargetPlatform.iOS
      ? Uri.parse('https://apps.apple.com/account/subscriptions')
      : Uri.parse('https://play.google.com/store/account/subscriptions');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    showKandoToast(context, message: 'Unable to open subscriptions.');
  }
}

class _PaywallBackground extends StatelessWidget {
  const _PaywallBackground({required this.sheet});

  final bool sheet;

  @override
  Widget build(BuildContext context) {
    if (sheet) {
      return Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF191813), KandoColors.ink],
                  stops: [0, 0.42],
                ),
              ),
            ),
          ),
          const Positioned(
            top: 8,
            right: -28,
            child: _SheetBackgroundCard(
              assetIndex: 4,
              width: 170,
              angle: -0.56,
              opacity: 0.34,
            ),
          ),
          const Positioned(
            top: 64,
            right: 82,
            child: _SheetBackgroundCard(
              assetIndex: 2,
              width: 150,
              angle: -0.87,
              opacity: 0.2,
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Color(0x0010100B), KandoColors.ink],
                  stops: [0.1, 0.44],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned(
          top: -70,
          left: -35,
          right: -35,
          height: 300,
          child: Transform.rotate(
            angle: -0.13,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 0.72,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: 12,
              itemBuilder: (context, index) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/subscription/card_${index % 7 + 1}.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color(0x3310100B), KandoColors.ink],
                stops: [0, 0.42],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetBackgroundCard extends StatelessWidget {
  const _SheetBackgroundCard({
    required this.assetIndex,
    required this.width,
    required this.angle,
    required this.opacity,
  });

  final int assetIndex;
  final double width;
  final double angle;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Opacity(
        opacity: opacity,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Color(0xFF677020),
            BlendMode.modulate,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/subscription/card_$assetIndex.png',
              width: width,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: KandoColors.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KandoColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: KandoColors.accentGlow10,
            ),
            child: const Icon(Icons.check, size: 15, color: KandoColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: KandoColors.text, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final SubscriptionPlanPresentation plan;
  final String price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          key: Key('subscription-plan-${plan.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 76,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: KandoColors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? KandoColors.accent : KandoColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? KandoColors.accent : KandoColors.border,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    plan.title,
                    style: const TextStyle(
                      color: KandoColors.text,
                      fontSize: 18,
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        color: KandoColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      plan.periodLabel,
                      style: const TextStyle(
                        color: KandoColors.mutedText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (plan.badge != null)
          Positioned(
            right: 16,
            top: -10,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4F20),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: KandoColors.borderFocus),
              ),
              child: Text(
                plan.badge!,
                style: const TextStyle(
                  color: KandoColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: KandoColors.surface.withValues(alpha: 0.9),
        foregroundColor: KandoColors.text,
        side: const BorderSide(color: KandoColors.border),
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.onTap});

  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        try {
          await onTap();
        } on Exception {
          if (context.mounted) {
            showKandoToast(context, message: 'Unable to open this page.');
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: const TextStyle(color: KandoColors.mutedText, fontSize: 12),
        ),
      ),
    );
  }
}
