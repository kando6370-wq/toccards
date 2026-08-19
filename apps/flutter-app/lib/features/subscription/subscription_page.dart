import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/premium_unlocked_toast.dart';
import 'package:kando_app/shared/ui/subscription_restore_result.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../profile/profile_actions.dart';
import 'subscription_controller.dart';

const _benefits = [
  'Unlimited Card Scanning',
  'Unlimited Portfolio Folders',
  'Track Portfolio Performance',
  'Extended Price History',
];

const _subscriptionSheetBackgroundAsset =
    'assets/subscription/sheet_background_1651_9915.png';
const _subscriptionSuccessTrophyAsset =
    'assets/subscription/success_trophy_2090_17166.svg';
const _subscriptionSheetItemBorder = Color(0xFF2A2D20);
const _subscriptionSheetSelectedSurface = Color(0xFF38372D);
const _subscriptionSheetSecondaryText = Color(0xFF999578);
const _subscriptionSheetSelectionPhaseDuration = Duration(milliseconds: 140);

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
        ref
            .read(subscriptionControllerProvider.notifier)
            .refreshProducts(isContextActive: () => mounted),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(subscriptionControllerProvider);
    final useUpdatedSkuUi = defaultTargetPlatform == TargetPlatform.iOS;
    final useUpdatedSheetUi = widget.sheet && useUpdatedSkuUi;
    ref.listen(subscriptionControllerProvider, (previous, next) {
      if (next.resultEventCount != previous?.resultEventCount &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
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
              showSubscriptionRestoreResult(
                context,
                type: SubscriptionRestoreResultType.premiumRestored,
              );
              context.canPop()
                  ? context.pop()
                  : context.go(_subscriptionSourceLocation(widget.source));
            }
          case SubscriptionResultEvent.restoreNotFound:
            showSubscriptionRestoreResult(
              context,
              type: SubscriptionRestoreResultType.notFound,
            );
          case SubscriptionResultEvent.restoreFailed:
            showSubscriptionRestoreResult(
              context,
              type: SubscriptionRestoreResultType.failed,
            );
          case SubscriptionResultEvent.externalPremium:
            if (widget.sheet && context.canPop()) {
              context.pop(SubscriptionPaywallResult.premiumUnlocked);
            } else if (widget.source == 'scan' && context.canPop()) {
              context.pop(SubscriptionPaywallResult.premiumUnlocked);
            } else {
              showPremiumUnlockedToast(context);
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
        showKandoTopToast(
          context,
          message: next.errorMessage!,
          type: KandoTopToastType.failure,
        );
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
          if (!useUpdatedSheetUi)
            Positioned.fill(
              child: _PaywallBackground(
                sheet: widget.sheet,
                useUpdatedSheetUi: false,
              ),
            ),
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
                    ..._benefits.map(
                      (benefit) => _BenefitRow(
                        benefit,
                        useUpdatedSheetUi: useUpdatedSheetUi,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ...subscriptionPlans.map(
                      (plan) => Padding(
                        padding: EdgeInsets.only(
                          bottom:
                              useUpdatedSkuUi &&
                                  plan.id != subscriptionLifetimePlanId
                              ? 22
                              : 12,
                        ),
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
                          useUpdatedSheetUi: useUpdatedSkuUi,
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
                if (useUpdatedSheetUi)
                  const Positioned.fill(
                    child: _PaywallBackground(
                      sheet: true,
                      useUpdatedSheetUi: true,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: content,
                ),
                Positioned(
                  top: useUpdatedSheetUi ? 21 : 10,
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
    } else if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
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
      backgroundColor: const Color(0xFF070905),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                children: [
                  const SizedBox(
                    key: Key('subscription-success-premium-active'),
                    height: 18,
                    child: Center(
                      child: Text(
                        'PREMIUM ACTIVE',
                        style: TextStyle(
                          color: Color(0xFFE5FF3B),
                          fontSize: 13,
                          height: 18 / 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 59),
                  _SuccessBadgeReveal(controller: _controller),
                  const SizedBox(height: 14),
                  _SuccessReveal(
                    key: const Key('subscription-success-title-reveal'),
                    controller: _controller,
                    begin: 0.29545,
                    end: 0.40909,
                    child: const SizedBox(
                      width: 350,
                      height: 40,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "You're Premium!",
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            color: Color(0xFFE3E3D6),
                            fontFamily: 'Fraunces',
                            fontSize: 32,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  _SuccessReveal(
                    controller: _controller,
                    begin: 0.29545,
                    end: 0.40909,
                    child: const SizedBox(
                      width: 322,
                      height: 22,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Your premium features are now unlocked.',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            color: Color(0xFFC8C8B1),
                            fontSize: 15,
                            height: 22 / 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
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
                  const SizedBox(height: 33),
                  _SuccessReveal(
                    key: const Key('subscription-success-button-reveal'),
                    controller: _controller,
                    begin: 0.80909,
                    end: 0.92273,
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        key: const Key('subscription-success-continue'),
                        style: FilledButton.styleFrom(
                          backgroundColor: KandoColors.accent,
                          foregroundColor: KandoColors.primaryOnDefault,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 16,
                          ),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            height: 24 / 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
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
      width: 208,
      height: 208,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 208,
            height: 208,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x1AE6FF3B),
            ),
          ),
          Container(
            width: 166,
            height: 166,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x29E6FF3B),
            ),
          ),
          Container(
            width: 116,
            height: 116,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF404D1A),
              border: Border.all(color: const Color(0xFFE6FF3B), width: 1.5),
            ),
            child: SvgPicture.asset(
              _subscriptionSuccessTrophyAsset,
              width: 60,
              height: 52,
            ),
          ),
          const _SuccessConfetti(
            left: -21,
            top: 41,
            size: 7,
            angle: 0.418879,
            color: Color(0xFFE5FF3B),
          ),
          const _SuccessConfetti(
            left: 210,
            top: 48,
            size: 6,
            angle: -0.488692,
            color: Color(0xFFF0F0E0),
          ),
          const _SuccessConfetti(
            left: -6,
            top: 161,
            size: 5,
            angle: 0.418879,
            color: Color(0xFFF0F0E0),
          ),
          const _SuccessConfetti(
            left: 198,
            top: 162,
            size: 8,
            angle: -0.488692,
            color: Color(0xFFE5FF3B),
          ),
          const _SuccessConfetti(
            left: 26,
            top: -9,
            size: 5,
            angle: 0.418879,
            color: Color(0xFFE5FF3B),
          ),
          const _SuccessConfetti(
            left: 180,
            top: -5,
            size: 5,
            angle: -0.488692,
            color: Color(0xFFF0F0E0),
          ),
          const _SuccessConfetti(
            left: -37,
            top: 111,
            size: 4,
            angle: 0.418879,
            color: Color(0xFFE5FF3B),
          ),
          const _SuccessConfetti(
            left: 236,
            top: 114,
            size: 4,
            angle: -0.488692,
            color: Color(0xFFF0F0E0),
          ),
        ],
      ),
    );
  }
}

class _SuccessConfetti extends StatelessWidget {
  const _SuccessConfetti({
    required this.left,
    required this.top,
    required this.size,
    required this.angle,
    required this.color,
  });

  final double left;
  final double top;
  final double size;
  final double angle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
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
        color: const Color(0xFF1E2018),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x4D474836)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: KandoColors.accent,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 14,
              color: KandoColors.primaryOnDefault,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: KandoColors.mutedText,
                fontSize: 14,
                height: 20 / 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaywallBackground extends StatelessWidget {
  const _PaywallBackground({
    required this.sheet,
    required this.useUpdatedSheetUi,
  });

  final bool sheet;
  final bool useUpdatedSheetUi;

  @override
  Widget build(BuildContext context) {
    if (useUpdatedSheetUi) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final imageWidth = constraints.maxWidth + 2;
          return ColoredBox(
            color: const Color(0xFF222222),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: imageWidth,
                maxWidth: imageWidth,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: const Offset(0, -1),
                  child: Image.asset(
                    _subscriptionSheetBackgroundAsset,
                    width: imageWidth,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topLeft,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
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
  const _BenefitRow(this.label, {required this.useUpdatedSheetUi});

  final String label;
  final bool useUpdatedSheetUi;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(horizontal: useUpdatedSheetUi ? 13 : 12),
      decoration: BoxDecoration(
        color: useUpdatedSheetUi
            ? KandoColors.surface.withValues(alpha: 0.4)
            : KandoColors.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: useUpdatedSheetUi
              ? _subscriptionSheetItemBorder
              : KandoColors.borderSubtle,
        ),
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
    if (!useUpdatedSheetUi) return row;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: row,
      ),
    );
  }
}

class _PlanTile extends StatefulWidget {
  const _PlanTile({
    required this.plan,
    required this.price,
    required this.selected,
    required this.enabled,
    required this.useUpdatedSheetUi,
    required this.onTap,
  });

  final SubscriptionPlanPresentation plan;
  final String price;
  final bool selected;
  final bool enabled;
  final bool useUpdatedSheetUi;
  final VoidCallback onTap;

  @override
  State<_PlanTile> createState() => _PlanTileState();
}

class _PlanTileState extends State<_PlanTile> {
  late bool _visualSelected;
  var _transitionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _visualSelected = widget.selected;
  }

  @override
  void didUpdateWidget(covariant _PlanTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.useUpdatedSheetUi) {
      _visualSelected = widget.selected;
      return;
    }
    if (oldWidget.selected == widget.selected) return;

    final generation = ++_transitionGeneration;
    if (!widget.selected) {
      _visualSelected = false;
      return;
    }

    _visualSelected = false;
    Future<void>.delayed(_subscriptionSheetSelectionPhaseDuration, () {
      if (!mounted || generation != _transitionGeneration || !widget.selected) {
        return;
      }
      setState(() => _visualSelected = true);
    });
  }

  @override
  void dispose() {
    _transitionGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final price = widget.price;
    final selected = widget.selected;
    final enabled = widget.enabled;
    final useUpdatedSheetUi = widget.useUpdatedSheetUi;
    final isSelected = useUpdatedSheetUi ? selected : selected && enabled;
    final visualSelected = useUpdatedSheetUi ? _visualSelected : isSelected;
    final usesPrimaryText = enabled || isSelected;
    final titleStyle = TextStyle(
      color: usesPrimaryText ? KandoColors.text : KandoColors.mutedText,
      fontSize: 18,
      fontWeight: useUpdatedSheetUi ? FontWeight.w500 : null,
      height: useUpdatedSheetUi ? 22 / 18 : null,
    );
    final priceStyle = TextStyle(
      color: usesPrimaryText ? KandoColors.text : KandoColors.mutedText,
      fontSize: useUpdatedSheetUi && !visualSelected ? 16 : 18,
      fontWeight: visualSelected ? FontWeight.w700 : FontWeight.w600,
      height: useUpdatedSheetUi
          ? visualSelected
                ? 27 / 18
                : 24 / 16
          : null,
    );
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: useUpdatedSheetUi ? 17 : 16),
      child: Row(
        children: [
          if (useUpdatedSheetUi)
            _SheetPlanRadio(selected: visualSelected, enabled: enabled)
          else
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? KandoColors.accent : KandoColors.border,
              size: 22,
            ),
          SizedBox(width: useUpdatedSheetUi ? 16 : 14),
          Expanded(
            child: useUpdatedSheetUi
                ? AnimatedDefaultTextStyle(
                    duration: _subscriptionSheetSelectionPhaseDuration,
                    curve: Curves.easeOutCubic,
                    style: titleStyle,
                    child: Text(plan.title),
                  )
                : Text(plan.title, style: titleStyle),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (useUpdatedSheetUi)
                AnimatedDefaultTextStyle(
                  duration: _subscriptionSheetSelectionPhaseDuration,
                  curve: Curves.easeOutCubic,
                  style: priceStyle,
                  child: Text(price),
                )
              else
                Text(price, style: priceStyle),
              Text(
                plan.periodLabel,
                style: TextStyle(
                  color: useUpdatedSheetUi
                      ? _subscriptionSheetSecondaryText
                      : KandoColors.mutedText,
                  fontSize: 12,
                  height: useUpdatedSheetUi ? 16 / 12 : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final surface = useUpdatedSheetUi
        ? SizedBox(
            key: Key('subscription-plan-${plan.id}-surface'),
            height: 74,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  key: Key('subscription-plan-${plan.id}-unselected-surface'),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1C1E15), Color(0xFF12140D)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _subscriptionSheetItemBorder),
                  ),
                ),
                AnimatedOpacity(
                  key: Key('subscription-plan-${plan.id}-selected-overlay'),
                  opacity: visualSelected ? 1 : 0,
                  duration: _subscriptionSheetSelectionPhaseDuration,
                  curve: Curves.easeOutCubic,
                  child: DecoratedBox(
                    key: Key('subscription-plan-${plan.id}-selected-surface'),
                    decoration: BoxDecoration(
                      color: _subscriptionSheetSelectedSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KandoColors.accent),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26F0FE6F),
                          blurRadius: 15,
                          spreadRadius: -3,
                        ),
                        BoxShadow(
                          color: Color(0x1AF0FE6F),
                          blurRadius: 6,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                  ),
                ),
                content,
              ],
            ),
          )
        : AnimatedContainer(
            key: Key('subscription-plan-${plan.id}-surface'),
            duration: const Duration(milliseconds: 160),
            height: 76,
            decoration: BoxDecoration(
              color: KandoColors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? KandoColors.accent : KandoColors.border,
              ),
            ),
            child: content,
          );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          key: Key('subscription-plan-${plan.id}'),
          onTap: enabled ? widget.onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: surface,
        ),
        if (plan.badge != null)
          Positioned(
            right: 16,
            top: useUpdatedSheetUi ? -12 : -10,
            child: _PlanBadge(
              planId: plan.id,
              label: plan.badge!,
              selected: visualSelected,
              useUpdatedSheetUi: useUpdatedSheetUi,
            ),
          ),
      ],
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({
    required this.planId,
    required this.label,
    required this.selected,
    required this.useUpdatedSheetUi,
  });

  final String planId;
  final String label;
  final bool selected;
  final bool useUpdatedSheetUi;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: useUpdatedSheetUi
          ? selected
                ? const Color(0x33F1FE70)
                : const Color(0xFF34362D)
          : const Color(0xFF4A4F20),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: useUpdatedSheetUi
            ? selected
                  ? const Color(0x4DF1FE70)
                  : const Color(0x4D474836)
            : KandoColors.borderFocus,
      ),
    );
    final badgeChild = Text(
      label,
      style: TextStyle(
        color: KandoColors.accent,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        height: useUpdatedSheetUi ? 1.5 : null,
        letterSpacing: 0,
      ),
    );
    if (!useUpdatedSheetUi) {
      return Container(
        key: Key('subscription-plan-$planId-badge-surface'),
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: decoration,
        child: badgeChild,
      );
    }
    final badge = AnimatedContainer(
      key: Key('subscription-plan-$planId-badge-surface'),
      duration: _subscriptionSheetSelectionPhaseDuration,
      curve: Curves.easeOutCubic,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: decoration,
      child: badgeChild,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        key: Key('subscription-plan-$planId-badge-blur'),
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: badge,
      ),
    );
  }
}

class _SheetPlanRadio extends StatelessWidget {
  const _SheetPlanRadio({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? KandoColors.accent
        : enabled
        ? KandoColors.border
        : KandoColors.border.withValues(alpha: 0.45);
    return AnimatedContainer(
      duration: _subscriptionSheetSelectionPhaseDuration,
      curve: Curves.easeOutCubic,
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.667),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x66F1FE70), blurRadius: 6.667)]
            : null,
      ),
      child: AnimatedContainer(
        duration: _subscriptionSheetSelectionPhaseDuration,
        curve: Curves.easeOutCubic,
        width: selected ? 8.333 : 0,
        height: selected ? 8.333 : 0,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: KandoColors.accent,
        ),
      ),
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
                  showKandoTopToast(
                    context,
                    message: 'Unable to open this page.',
                    type: KandoTopToastType.failure,
                  );
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
