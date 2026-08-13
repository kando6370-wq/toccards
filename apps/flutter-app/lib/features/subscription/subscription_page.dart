import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/kando_modal.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../profile/profile_actions.dart';
import 'subscription_controller.dart';

const _benefits = [
  'Unlimited Card Scanning',
  'Unlimited Portfolio Folders',
  'Track Portfolio Performance',
  'Extended Price History',
];

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({
    this.sheet = false,
    this.source,
    this.entrySource,
    super.key,
  });

  final bool sheet;
  final String? source;
  final String? entrySource;

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(subscriptionControllerProvider.notifier).refreshProducts(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(subscriptionControllerProvider);
    ref.listen(subscriptionControllerProvider, (previous, next) {
      if (next.resultEventCount != previous?.resultEventCount &&
          context.mounted) {
        switch (next.resultEvent) {
          case SubscriptionResultEvent.purchaseSuccess:
            if (widget.sheet && context.canPop()) {
              context.pop(SubscriptionPaywallResult.premiumUnlocked);
            } else if (widget.source == 'scan' ||
                _preservesSourcePage(widget.source)) {
              unawaited(
                _showSourceSubscriptionSuccess(
                  context,
                  source: widget.source!,
                  entrySource: widget.entrySource,
                ),
              );
            } else {
              context.go(_subscriptionSuccessLocation(widget.source));
            }
          case SubscriptionResultEvent.restoreSuccess:
            if (widget.sheet && context.canPop()) {
              context.pop(SubscriptionPaywallResult.premiumRestored);
            } else if (widget.source == 'scan' && context.canPop()) {
              context.pop(SubscriptionPaywallResult.premiumRestored);
            } else {
              showKandoCenteredSuccessToast(
                context,
                title: 'Premium restored',
                message: 'Your premium access is ready to use.',
                duration: const Duration(milliseconds: 2750),
              );
              context.canPop()
                  ? context.pop()
                  : context.go(_subscriptionSourceLocation(widget.source));
            }
          case SubscriptionResultEvent.restoreNotFound:
            showKandoTopToast(
              context,
              message: 'No subscription found',
              type: KandoTopToastType.info,
            );
          case SubscriptionResultEvent.restoreFailed:
            showKandoFailureAlert(
              context,
              title: 'Restore failed',
              message: 'Unable to restore purchases. Please try again.',
            );
          case SubscriptionResultEvent.externalPremium:
            if (widget.sheet && context.canPop()) {
              context.pop(SubscriptionPaywallResult.premiumUnlocked);
            } else if (widget.source == 'scan' && context.canPop()) {
              context.pop(SubscriptionPaywallResult.premiumUnlocked);
            } else {
              showKandoTopToast(
                context,
                message: 'Premium unlocked',
                type: KandoTopToastType.success,
              );
              context.canPop()
                  ? context.pop()
                  : context.go(_subscriptionSourceLocation(widget.source));
            }
          case null:
            break;
        }
      }
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage &&
          context.mounted) {
        showKandoToast(context, message: next.errorMessage!);
      }
    });

    final content = PopScope(
      canPop: !state.isRestoring && !state.isPurchasing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && state.isPurchasePending) {
          ref
              .read(subscriptionControllerProvider.notifier)
              .abandonPurchasePresentation();
        }
      },
      child: Stack(
        children: [
          Positioned.fill(child: _PaywallBackground(sheet: widget.sheet)),
          CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 98)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverList.list(
                  children: [
                    const Text(
                      'Choose Your Plan',
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
                              state.displayPrices[plan.id] ??
                              (state.isLoading ? 'Loading' : 'Unavailable'),
                          selected:
                              state.selectedPlanId == plan.id &&
                              state.availablePlanIds.contains(plan.id),
                          enabled:
                              state.availablePlanIds.contains(plan.id) &&
                              !state.isLoading &&
                              !state.isPurchasing &&
                              !state.isPurchasePending,
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
                        onPressed:
                            state.isLoading ||
                                state.isPurchasing ||
                                state.isPurchasePending
                            ? null
                            : () => ref
                                  .read(subscriptionControllerProvider.notifier)
                                  .purchase(),
                        style: FilledButton.styleFrom(
                          backgroundColor: KandoColors.accent,
                          foregroundColor: KandoColors.primaryOnDefault,
                          disabledBackgroundColor: KandoColors.accent
                              .withValues(alpha: 0.45),
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
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _LegalLink(
                          label: 'Terms of Use',
                          onTap: state.isLoading || state.isPurchasing
                              ? null
                              : () => ref
                                    .read(profileActionsProvider)
                                    .openTerms(),
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
                          onTap: state.isLoading || state.isPurchasing
                              ? null
                              : () => ref
                                    .read(profileActionsProvider)
                                    .openPrivacy(),
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
              onPressed: state.isPurchasing || state.isRestoring
                  ? null
                  : () {
                      ref
                          .read(subscriptionControllerProvider.notifier)
                          .abandonPurchasePresentation();
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(_subscriptionSourceLocation(widget.source));
                      }
                    },
            ),
          ),
          Positioned(
            top: 12,
            right: 20,
            child: TextButton(
              onPressed:
                  state.isLoading ||
                      state.isPurchasing ||
                      state.isPurchasePending
                  ? null
                  : () => ref
                        .read(subscriptionControllerProvider.notifier)
                        .restore(
                          source: SubscriptionRestoreSource.subscriptionPage,
                        ),
              child: const Text('Restore'),
            ),
          ),
          if (state.isRestoring)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x99000000),
                child: Center(
                  child: CircularProgressIndicator(color: KandoColors.accent),
                ),
              ),
            ),
        ],
      ),
    );
    if (!widget.sheet) {
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

Future<void> _showSourceSubscriptionSuccess(
  BuildContext context, {
  required String source,
  String? entrySource,
}) async {
  final result = await context.push<SubscriptionPaywallResult>(
    Uri(
      path: '/subscription/success',
      queryParameters: {
        'source': source,
        if (entrySource != null) 'entry_source': entrySource,
      },
    ).toString(),
  );
  if (context.mounted && result != null && context.canPop()) {
    context.pop(result);
  }
}

bool _preservesSourcePage(String? source) =>
    source == 'home' ||
    source == 'search' ||
    source == 'collection' ||
    source == 'profile';

String _subscriptionSuccessLocation(String? source) {
  return Uri(
    path: '/subscription/success',
    queryParameters: source == null ? null : {'source': source},
  ).toString();
}

String _subscriptionSourceLocation(String? source) {
  return switch (source) {
    'profile' => '/profile',
    'search' => '/search',
    'collection' => '/collection',
    _ => '/home',
  };
}

class SubscriptionSuccessPage extends StatefulWidget {
  const SubscriptionSuccessPage({this.source, this.entrySource, super.key});

  final String? source;
  final String? entrySource;

  @override
  State<SubscriptionSuccessPage> createState() =>
      _SubscriptionSuccessPageState();
}

class _SubscriptionSuccessPageState extends State<SubscriptionSuccessPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      _controller
        ..stop()
        ..value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
                  _SuccessBadgeReveal(controller: _controller),
                  const SizedBox(height: 25),
                  _SuccessReveal(
                    key: const Key('subscription-success-title-reveal'),
                    controller: _controller,
                    begin: 0.29545,
                    end: 0.40909,
                    child: const Text(
                      "You're Premium!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: KandoColors.text,
                        fontFamily: 'Fraunces',
                        fontSize: 32,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SuccessReveal(
                    controller: _controller,
                    begin: 0.29545,
                    end: 0.40909,
                    child: const Text(
                      'Your premium features are now unlocked.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: KandoColors.text,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  _SuccessReveal(
                    key: const Key('subscription-success-benefit-0-reveal'),
                    controller: _controller,
                    begin: 0.52273,
                    end: 0.63636,
                    child: const _SuccessBenefitRow('Unlimited Card Scanning'),
                  ),
                  const SizedBox(height: 12),
                  _SuccessReveal(
                    key: const Key('subscription-success-benefit-1-reveal'),
                    controller: _controller,
                    begin: 0.55,
                    end: 0.66364,
                    child: const _SuccessBenefitRow(
                      'Unlimited Portfolio Folders',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SuccessReveal(
                    key: const Key('subscription-success-benefit-2-reveal'),
                    controller: _controller,
                    begin: 0.57727,
                    end: 0.69091,
                    child: const _SuccessBenefitRow(
                      'Track Portfolio Performance',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SuccessReveal(
                    key: const Key('subscription-success-benefit-3-reveal'),
                    controller: _controller,
                    begin: 0.60455,
                    end: 0.71818,
                    child: const _SuccessBenefitRow('Extended Price History'),
                  ),
                  const SizedBox(height: 44),
                  _SuccessReveal(
                    controller: _controller,
                    begin: 0.80909,
                    end: 0.92273,
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        key: const Key('subscription-success-continue'),
                        onPressed: () {
                          if ((widget.source == 'scan' ||
                                  _preservesSourcePage(widget.source)) &&
                              context.canPop()) {
                            context.pop(
                              SubscriptionPaywallResult.premiumUnlocked,
                            );
                          } else {
                            context.go(
                              _subscriptionSourceLocation(widget.source),
                            );
                          }
                        },
                        child: const Text('START EXPLORING'),
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

class _SuccessReveal extends StatelessWidget {
  const _SuccessReveal({
    required this.controller,
    required this.begin,
    required this.end,
    required this.child,
    super.key,
  });

  final AnimationController controller;
  final double begin;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final progress = Interval(
          begin,
          end,
          curve: Curves.easeOut,
        ).transform(controller.value);
        return IgnorePointer(
          ignoring: progress < 1,
          child: Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - progress)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _SuccessBadgeReveal extends StatelessWidget {
  const _SuccessBadgeReveal({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: const _SuccessBadge(),
      builder: (context, child) {
        final value = controller.value;
        final opacity = const Interval(
          0.09091,
          0.29545,
          curve: Curves.easeOut,
        ).transform(value);
        final scale = value <= 0.21818
            ? 0.82 + (0.26 * Curves.easeOut.transform(value / 0.21818))
            : value < 0.29545
            ? 1.08 - (0.08 * ((value - 0.21818) / (0.29545 - 0.21818)))
            : 1.0;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
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
    required this.enabled,
    required this.onTap,
  });

  final SubscriptionPlanPresentation plan;
  final String price;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          key: Key('subscription-plan-${plan.id}'),
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 76,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: KandoColors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected && enabled
                    ? KandoColors.accent
                    : KandoColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected && enabled
                      ? KandoColors.accent
                      : KandoColors.border,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    plan.title,
                    style: TextStyle(
                      color: enabled ? KandoColors.text : KandoColors.mutedText,
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
                      style: TextStyle(
                        color: enabled
                            ? KandoColors.text
                            : KandoColors.mutedText,
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
  final VoidCallback? onPressed;

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
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () async {
              try {
                await onTap!();
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
