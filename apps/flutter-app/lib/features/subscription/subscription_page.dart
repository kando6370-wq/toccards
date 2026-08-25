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
import 'package:video_player/video_player.dart';

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
const _subscriptionFullPageBackgroundVideoAsset =
    'assets/subscription/card-bg.mp4';
const _subscriptionFullPageBackgroundVideoAspectRatio = 608 / 1080;
const _subscriptionSuccessTrophyAsset =
    'assets/subscription/success_trophy_2090_17166.svg';
// Figma 2090:17166 uses one shared normalized timeline for all 24 nodes.
const _subscriptionSuccessMotionDuration = Duration(milliseconds: 2350);
const _successRevealCurve = Cubic(0.22, 1, 0.36, 1);
const _successSwiftOutCurve = Cubic(0.16, 1, 0.3, 1);
const _successOvershootCurve = Cubic(0.34, 1.28, 0.64, 1);
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
    Future<void>.microtask(() {
      if (!mounted) return;
      ref
          .read(subscriptionControllerProvider.notifier)
          .resetPlanSelectionForNewPresentation();
    });
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
              child: _PaywallBackground(useUpdatedSheetUi: false),
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
                          price: state.displayPriceFor(plan.id),
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
      key: const Key('subscription-sheet-surface'),
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
                    child: _PaywallBackground(useUpdatedSheetUi: true),
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
    duration: _subscriptionSuccessMotionDuration,
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
                  _SuccessReveal(
                    key: const Key(
                      'subscription-success-premium-active-reveal',
                    ),
                    controller: _controller,
                    begin: 0.05106,
                    end: 0.22979,
                    offsetY: 8,
                    child: const SizedBox(
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
                  ),
                  const SizedBox(height: 59),
                  _SuccessBadge(controller: _controller),
                  const SizedBox(height: 14),
                  _SuccessReveal(
                    key: const Key('subscription-success-title-reveal'),
                    controller: _controller,
                    begin: 0.24681,
                    end: 0.42553,
                    offsetY: 18,
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
                    begin: 0.31064,
                    end: 0.48936,
                    offsetY: 14,
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
                    begin: 0.41702,
                    end: 0.59574,
                    offsetY: 16,
                    child: _SuccessBenefitRow(
                      'Unlimited Card Scanning',
                      controller: _controller,
                      index: 0,
                      checkOpacityBegin: 0.52766,
                      checkOpacityEnd: 0.56170,
                      checkDrawEnd: 0.62979,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SuccessReveal(
                    key: const Key('subscription-success-benefit-1-reveal'),
                    controller: _controller,
                    begin: 0.47660,
                    end: 0.65532,
                    offsetY: 16,
                    child: _SuccessBenefitRow(
                      'Unlimited Portfolio Folders',
                      controller: _controller,
                      index: 1,
                      checkOpacityBegin: 0.58723,
                      checkOpacityEnd: 0.62128,
                      checkDrawEnd: 0.68936,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SuccessReveal(
                    key: const Key('subscription-success-benefit-2-reveal'),
                    controller: _controller,
                    begin: 0.53617,
                    end: 0.71489,
                    offsetY: 16,
                    child: _SuccessBenefitRow(
                      'Track Portfolio Performance',
                      controller: _controller,
                      index: 2,
                      checkOpacityBegin: 0.64681,
                      checkOpacityEnd: 0.68085,
                      checkDrawEnd: 0.74894,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SuccessReveal(
                    key: const Key('subscription-success-benefit-3-reveal'),
                    controller: _controller,
                    begin: 0.59574,
                    end: 0.77447,
                    offsetY: 16,
                    child: _SuccessBenefitRow(
                      'Extended Price History',
                      controller: _controller,
                      index: 3,
                      checkOpacityBegin: 0.70638,
                      checkOpacityEnd: 0.74043,
                      checkDrawEnd: 0.80851,
                    ),
                  ),
                  const SizedBox(height: 33),
                  _SuccessReveal(
                    key: const Key('subscription-success-button-reveal'),
                    controller: _controller,
                    begin: 0.71489,
                    end: 0.89362,
                    offsetY: 18,
                    initialScale: 0.96,
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
    required this.offsetY,
    this.initialScale = 1,
    super.key,
  });

  final AnimationController controller;
  final double begin;
  final double end;
  final double offsetY;
  final double initialScale;
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
          curve: _successRevealCurve,
        ).transform(controller.value);
        return IgnorePointer(
          ignoring: progress < 1,
          child: Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, offsetY * (1 - progress)),
              child: Transform.scale(
                scale: ui.lerpDouble(initialScale, 1, progress)!,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('subscription-success-badge'),
      width: 208,
      height: 208,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final value = controller.value;
          final outerGlowOpacity = value < 0.09362
              ? _motionTween(
                  value,
                  begin: 0,
                  end: 0.09362,
                  from: 0,
                  to: 0.22,
                  curve: _successSwiftOutCurve,
                )
              : _motionTween(
                  value,
                  begin: 0.09362,
                  end: 0.45957,
                  from: 0.22,
                  to: 0,
                  curve: Curves.easeOut,
                );
          final innerGlowOpacity = value < 0.05957
              ? _motionTween(
                  value,
                  begin: 0,
                  end: 0.05957,
                  from: 0,
                  to: 0.3,
                  curve: _successSwiftOutCurve,
                )
              : _motionTween(
                  value,
                  begin: 0.05957,
                  end: 0.37447,
                  from: 0.3,
                  to: 0,
                  curve: Curves.easeOut,
                );
          final medallionOpacity = _motionTween(
            value,
            begin: 0,
            end: 0.06809,
            from: 0,
            to: 1,
            curve: _successSwiftOutCurve,
          );
          final medallionScale = value < 0.15319
              ? _motionTween(
                  value,
                  begin: 0,
                  end: 0.15319,
                  from: 0.74,
                  to: 1.055,
                  curve: _successOvershootCurve,
                )
              : _motionTween(
                  value,
                  begin: 0.15319,
                  end: 0.26383,
                  from: 1.055,
                  to: 1,
                  curve: _successSwiftOutCurve,
                );
          final trophyOpacity = _motionTween(
            value,
            begin: 0,
            end: 0.06809,
            from: 0,
            to: 1,
            curve: _successSwiftOutCurve,
          );
          final trophyOffsetY = value < 0.12766
              ? _motionTween(
                  value,
                  begin: 0,
                  end: 0.12766,
                  from: 20,
                  to: -4,
                  curve: _successSwiftOutCurve,
                )
              : _motionTween(
                  value,
                  begin: 0.12766,
                  end: 0.22128,
                  from: -4,
                  to: 0,
                  curve: Curves.easeInOut,
                );
          final trophyScale = value < 0.12766
              ? _motionTween(
                  value,
                  begin: 0,
                  end: 0.12766,
                  from: 0.72,
                  to: 1.1,
                  curve: _successOvershootCurve,
                )
              : value < 0.22128
              ? _motionTween(
                  value,
                  begin: 0.12766,
                  end: 0.22128,
                  from: 1.1,
                  to: 0.98,
                  curve: Curves.easeInOut,
                )
              : _motionTween(
                  value,
                  begin: 0.22128,
                  end: 0.29787,
                  from: 0.98,
                  to: 1,
                  curve: _successSwiftOutCurve,
                );

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              _SuccessMotionLayer(
                key: const Key('subscription-success-glow-outer'),
                opacity: outerGlowOpacity,
                scale: _motionTween(
                  value,
                  begin: 0,
                  end: 0.45957,
                  from: 0.7,
                  to: 1.22,
                  curve: Curves.easeOut,
                ),
                child: Container(
                  width: 208,
                  height: 208,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x1AE6FF3B),
                  ),
                ),
              ),
              _SuccessMotionLayer(
                key: const Key('subscription-success-glow-inner'),
                opacity: innerGlowOpacity,
                scale: _motionTween(
                  value,
                  begin: 0,
                  end: 0.37447,
                  from: 0.7,
                  to: 1.22,
                  curve: Curves.easeOut,
                ),
                child: Container(
                  width: 166,
                  height: 166,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x29E6FF3B),
                  ),
                ),
              ),
              _SuccessMotionLayer(
                key: const Key('subscription-success-medallion'),
                opacity: medallionOpacity,
                scale: medallionScale,
                child: Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF404D1A),
                    border: Border.all(
                      color: const Color(0xFFE6FF3B),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              _SuccessMotionLayer(
                key: const Key('subscription-success-trophy'),
                opacity: trophyOpacity,
                scale: trophyScale,
                offset: Offset(0, trophyOffsetY),
                child: SizedBox(
                  width: 82,
                  height: 82,
                  child: Center(
                    child: SvgPicture.asset(
                      _subscriptionSuccessTrophyAsset,
                      width: 60,
                      height: 52,
                    ),
                  ),
                ),
              ),
              for (var index = 0; index < _successConfettiSpecs.length; index++)
                _SuccessConfetti(
                  key: Key('subscription-success-confetti-$index'),
                  spec: _successConfettiSpecs[index],
                  timelineValue: value,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SuccessMotionLayer extends StatelessWidget {
  const _SuccessMotionLayer({
    required this.opacity,
    required this.child,
    this.scale = 1,
    this.offset = Offset.zero,
    super.key,
  });

  final double opacity;
  final double scale;
  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0, 1),
      child: Transform.translate(
        offset: offset,
        child: Transform.scale(scale: scale, child: child),
      ),
    );
  }
}

class _SuccessConfetti extends StatelessWidget {
  const _SuccessConfetti({
    required this.spec,
    required this.timelineValue,
    super.key,
  });

  final _SuccessConfettiSpec spec;
  final double timelineValue;

  @override
  Widget build(BuildContext context) {
    final opacity = timelineValue < spec.visibleAt
        ? _motionTween(
            timelineValue,
            begin: spec.startsAt,
            end: spec.visibleAt,
            from: 0,
            to: 1,
            curve: _successSwiftOutCurve,
          )
        : _motionTween(
            timelineValue,
            begin: spec.visibleAt,
            end: spec.endsAt,
            from: 1,
            to: 0,
            curve: Curves.easeIn,
          );
    final movement = _motionProgress(
      timelineValue,
      begin: spec.startsAt,
      end: spec.endsAt,
      curve: Curves.easeOut,
    );
    return Positioned(
      left: spec.left,
      top: spec.top,
      child: Transform.translate(
        offset: Offset(spec.dx * movement, spec.dy * movement),
        child: Opacity(
          opacity: opacity.clamp(0, 1),
          child: Transform.rotate(
            angle: ui.lerpDouble(spec.angle, spec.endAngle, movement)!,
            child: Container(
              width: spec.size,
              height: spec.size,
              decoration: BoxDecoration(
                color: spec.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessConfettiSpec {
  const _SuccessConfettiSpec({
    required this.left,
    required this.top,
    required this.size,
    required this.angle,
    required this.endAngle,
    required this.color,
    required this.startsAt,
    required this.visibleAt,
    required this.endsAt,
    required this.dx,
    required this.dy,
  });

  final double left;
  final double top;
  final double size;
  final double angle;
  final double endAngle;
  final Color color;
  final double startsAt;
  final double visibleAt;
  final double endsAt;
  final double dx;
  final double dy;
}

const _successConfettiSpecs = [
  _SuccessConfettiSpec(
    left: -19.729,
    top: 42.121,
    size: 7,
    angle: 0.418879,
    endAngle: 2.373648,
    color: Color(0xFFE5FF3B),
    startsAt: 0.08085,
    visibleAt: 0.13617,
    endsAt: 0.48936,
    dx: -22,
    dy: -48,
  ),
  _SuccessConfettiSpec(
    left: 211.0575,
    top: 49.2375,
    size: 6,
    angle: -0.488692,
    endAngle: -2.443461,
    color: Color(0xFFF0F0E0),
    startsAt: 0.09191,
    visibleAt: 0.14723,
    endsAt: 0.49787,
    dx: 30,
    dy: -55,
  ),
  _SuccessConfettiSpec(
    left: -5.2295,
    top: 161.8005,
    size: 5,
    angle: 0.418879,
    endAngle: 2.373648,
    color: Color(0xFFF0F0E0),
    startsAt: 0.10298,
    visibleAt: 0.15830,
    endsAt: 0.50638,
    dx: -38,
    dy: -62,
  ),
  _SuccessConfettiSpec(
    left: 199.4095,
    top: 163.6495,
    size: 8,
    angle: -0.488692,
    endAngle: -2.443461,
    color: Color(0xFFE5FF3B),
    startsAt: 0.11404,
    visibleAt: 0.16936,
    endsAt: 0.51489,
    dx: 22,
    dy: -69,
  ),
  _SuccessConfettiSpec(
    left: 26.7705,
    top: -8.1995,
    size: 5,
    angle: 0.418879,
    endAngle: 2.373648,
    color: Color(0xFFE5FF3B),
    startsAt: 0.12511,
    visibleAt: 0.18043,
    endsAt: 0.52340,
    dx: -30,
    dy: -48,
  ),
  _SuccessConfettiSpec(
    left: 180.881,
    top: -4.469,
    size: 5,
    angle: -0.488692,
    endAngle: -2.443461,
    color: Color(0xFFF0F0E0),
    startsAt: 0.13617,
    visibleAt: 0.19149,
    endsAt: 0.53191,
    dx: 38,
    dy: -55,
  ),
  _SuccessConfettiSpec(
    left: -35.9895,
    top: 111.6405,
    size: 4,
    angle: 0.418879,
    endAngle: 2.373648,
    color: Color(0xFFE5FF3B),
    startsAt: 0.14723,
    visibleAt: 0.20255,
    endsAt: 0.54043,
    dx: -22,
    dy: -62,
  ),
  _SuccessConfettiSpec(
    left: 236.705,
    top: 114.825,
    size: 4,
    angle: -0.488692,
    endAngle: -2.443461,
    color: Color(0xFFF0F0E0),
    startsAt: 0.15830,
    visibleAt: 0.21362,
    endsAt: 0.54894,
    dx: 30,
    dy: -69,
  ),
];

double _motionProgress(
  double value, {
  required double begin,
  required double end,
  required Curve curve,
}) {
  if (value <= begin) return 0;
  if (value >= end) return 1;
  return curve.transform((value - begin) / (end - begin));
}

double _motionTween(
  double value, {
  required double begin,
  required double end,
  required double from,
  required double to,
  required Curve curve,
}) {
  return ui.lerpDouble(
    from,
    to,
    _motionProgress(value, begin: begin, end: end, curve: curve),
  )!;
}

class _SuccessBenefitRow extends StatelessWidget {
  const _SuccessBenefitRow(
    this.label, {
    required this.controller,
    required this.index,
    required this.checkOpacityBegin,
    required this.checkOpacityEnd,
    required this.checkDrawEnd,
  });

  final String label;
  final AnimationController controller;
  final int index;
  final double checkOpacityBegin;
  final double checkOpacityEnd;
  final double checkDrawEnd;

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
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final opacity = _motionTween(
                controller.value,
                begin: checkOpacityBegin,
                end: checkOpacityEnd,
                from: 0,
                to: 1,
                curve: _successSwiftOutCurve,
              );
              final drawProgress = _motionProgress(
                controller.value,
                begin: checkOpacityBegin,
                end: checkDrawEnd,
                curve: _successSwiftOutCurve,
              );
              return Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: KandoColors.accent,
                ),
                child: Opacity(
                  key: Key('subscription-success-checkmark-$index'),
                  opacity: opacity.clamp(0, 1),
                  child: CustomPaint(
                    size: const Size(9.7, 7.45),
                    painter: _SuccessCheckmarkPainter(drawProgress),
                  ),
                ),
              );
            },
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

class _SuccessCheckmarkPainter extends CustomPainter {
  const _SuccessCheckmarkPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 9.7;
    final scaleY = size.height / 7.45;
    canvas.scale(scaleX, scaleY);
    final path = Path()
      ..moveTo(0.85, 3.95)
      ..lineTo(3.6, 6.6)
      ..lineTo(8.85, 0.85);
    final paint = Paint()
      ..color = const Color(0xFF1E2018)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0, 1)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessCheckmarkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _PaywallBackground extends StatelessWidget {
  const _PaywallBackground({required this.useUpdatedSheetUi});

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
    return const _SubscriptionVideoBackground();
  }
}

class _SubscriptionVideoBackground extends StatefulWidget {
  const _SubscriptionVideoBackground();

  @override
  State<_SubscriptionVideoBackground> createState() =>
      _SubscriptionVideoBackgroundState();
}

class _SubscriptionVideoBackgroundState
    extends State<_SubscriptionVideoBackground>
    with WidgetsBindingObserver {
  static const _initializationTimeout = Duration(seconds: 4);

  VideoPlayerController? _controller;
  AppLifecycleState? _lifecycleState;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.asset(
      _subscriptionFullPageBackgroundVideoAsset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize().timeout(_initializationTimeout);
      if (!mounted || controller != _controller) return;
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted || controller != _controller) return;
      setState(() => _isReady = true);
      await _syncPlayback();
    } catch (_) {
      if (controller != _controller) return;
      _controller = null;
      if (mounted) setState(() => _isReady = false);
      await controller.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    unawaited(_syncPlayback());
  }

  Future<void> _syncPlayback() async {
    final controller = _controller;
    if (!_isReady || controller == null) return;
    try {
      if (_lifecycleState == null ||
          _lifecycleState == AppLifecycleState.resumed) {
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (_) {
      if (!mounted || controller != _controller) return;
      _controller = null;
      setState(() => _isReady = false);
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('subscription-video-background'),
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final videoWidth = constraints.maxWidth;
          final videoHeight =
              videoWidth / _subscriptionFullPageBackgroundVideoAspectRatio;
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minWidth: videoWidth,
              maxWidth: videoWidth,
              minHeight: videoHeight,
              maxHeight: videoHeight,
              child: SizedBox(
                key: const Key('subscription-video-frame'),
                width: videoWidth,
                height: videoHeight,
                child: _isReady && _controller != null
                    ? FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: _controller!.value.size.width,
                          height: _controller!.value.size.height,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          );
        },
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
