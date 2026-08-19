import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/card_image/kando_card_image.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/premium_locked_panel.dart';
import 'package:kando_app/shared/ui/premium_unlocked_toast.dart';
import 'package:kando_app/shared/ui/subscription_restore_result.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../../shared/analytics/analytics_events.dart';
import '../../shared/analytics/app_analytics.dart';
import '../collection/collection_page.dart';
import '../collection/collection_controller.dart';
import '../collection/collection_models.dart';
import '../subscription/subscription_controller.dart';
import '../subscription/subscription_entitlement_cache.dart';
import '../subscription/premium_top_entry.dart';
import 'home_controller.dart';
import 'home_models.dart';
import 'home_performance_controller.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  AppLifecycleState? _lastLifecycleState;
  var _performanceSelected = false;

  @override
  void initState() {
    super.initState();
    _lastLifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final returningFromBackground =
        state == AppLifecycleState.resumed &&
        _lastLifecycleState != null &&
        _lastLifecycleState != AppLifecycleState.resumed;
    _lastLifecycleState = state;
    if (returningFromBackground) {
      unawaited(ref.read(homeControllerProvider.notifier).refreshSilently());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);
    final premiumState = ref.watch(
      subscriptionControllerProvider.select((value) => value.premiumState),
    );
    final isPro = premiumState == AppPremiumState.premium;
    if (premiumState == AppPremiumState.free &&
        state.chartRange == HomeChartRange.oneYear) {
      Future<void>.microtask(
        () => ref
            .read(homeControllerProvider.notifier)
            .selectChartRange(HomeChartRange.threeMonths),
      );
    }
    final performance = ref.watch(homePerformanceControllerProvider);
    if (_performanceSelected &&
        isPro &&
        (performance.folderId != state.selectedFolderId ||
            !performance.hasLoaded && !performance.isLoading)) {
      Future<void>.microtask(
        () => ref
            .read(homePerformanceControllerProvider.notifier)
            .load(folderId: state.selectedFolderId, localPremiumVerified: true),
      );
    }

    return KandoTabScaffold(
      currentTab: KandoMainTab.home,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-1.05, -1.15),
            radius: 1.15,
            colors: [Color(0xFF3A4019), Color(0xFF1F2110), KandoColors.ink],
            stops: [0, .36, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            key: const Key('home-pull-to-refresh'),
            onRefresh: () => _trackRefresh(controller.refresh),
            child: SingleChildScrollView(
              key: const Key('home-normal-content'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                20,
                KandoLayout.mainTabTopPadding,
                20,
                132,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    currencyCode: state.currencyCode,
                    currencySymbol: state.currency.symbol,
                    performanceSelected: _performanceSelected,
                    onOverviewPressed: () {
                      setState(() => _performanceSelected = false);
                    },
                    onPerformancePressed: () {
                      setState(() => _performanceSelected = true);
                      unawaited(
                        _loadPerformanceIfPremium(state.selectedFolderId),
                      );
                    },
                    onCurrencyPressed: () {
                      ref
                          .read(analyticsProvider)
                          .track(AnalyticsEvent.currencyClick);
                      _showCurrencySheet(context, ref);
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_performanceSelected)
                    _PerformanceSection(
                      state: state,
                      performance: performance,
                      isPro: isPro,
                      onHidePressed: controller.toggleAmountHidden,
                      onFolderPressed: () => _showFolderSheet(context, ref),
                      onRangeSelected: (range) => ref
                          .read(homePerformanceControllerProvider.notifier)
                          .selectRange(
                            range,
                            folderId: state.selectedFolderId,
                            localPremiumVerified: true,
                          ),
                      onUnlock: () => _unlockPerformance(
                        context,
                        folderId: state.selectedFolderId,
                      ),
                      onRefresh: () => ref
                          .read(homePerformanceControllerProvider.notifier)
                          .load(
                            folderId: state.selectedFolderId,
                            localPremiumVerified: true,
                            force: true,
                          ),
                    )
                  else ...[
                    _PortfolioCard(
                      state: state,
                      showOneYearProBadge: !isPro,
                      onFolderPressed: () {
                        ref
                            .read(analyticsProvider)
                            .track(AnalyticsEvent.folderClick);
                        _showFolderSheet(context, ref);
                      },
                      onHidePressed: controller.toggleAmountHidden,
                      onRangeSelected: (range) => _selectOverviewRange(
                        context,
                        controller,
                        range,
                        premiumState: premiumState,
                      ),
                      onRefresh: () => _trackRefresh(controller.refresh),
                    ),
                    const SizedBox(height: 32),
                    _MostValuableSection(
                      state: state,
                      onRefresh: controller.refresh,
                      onViewAll: () {
                        ref
                            .read(analyticsProvider)
                            .track(AnalyticsEvent.mostvaluableClick);
                        ref
                            .read(collectionInitialSortProvider.notifier)
                            .select(CollectionSort.valueDesc);
                        context.go('/collection');
                      },
                    ),
                  ],
                  if (!_performanceSelected || isPro) ...[
                    const SizedBox(height: 32),
                    _TrendingSection(
                      state: state,
                      onRefresh: () =>
                          _trackRefresh(controller.refreshTrending),
                      onViewAll: () {
                        ref
                            .read(analyticsProvider)
                            .track(AnalyticsEvent.trendingClick);
                        context.push('/trending');
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFolderSheet(BuildContext context, WidgetRef ref) {
    return showPortfolioFolderSheet(context, ref);
  }

  Future<void> _trackRefresh(Future<void> Function() refresh) {
    ref.read(analyticsProvider).track(AnalyticsEvent.refreshClick);
    return refresh();
  }

  Future<void> _unlockPerformance(
    BuildContext context, {
    required String folderId,
  }) async {
    final premiumState = await _resolvePremiumForRestrictedAction();
    if (!mounted || !context.mounted) return;
    if (premiumState == AppPremiumState.premium) {
      await ref
          .read(homePerformanceControllerProvider.notifier)
          .load(folderId: folderId, localPremiumVerified: true, force: true);
      return;
    }
    if (premiumState == AppPremiumState.unknown) return;
    final result = await context.push<SubscriptionPaywallResult>(
      subscriptionSheetLocation,
    );
    if (!mounted || !context.mounted || result == null) return;
    if (result == SubscriptionPaywallResult.premiumRestored) {
      showSubscriptionRestoreResult(
        context,
        type: SubscriptionRestoreResultType.premiumRestored,
      );
    } else {
      showPremiumUnlockedToast(context);
    }
    final home = ref.read(homeControllerProvider);
    if (!_performanceSelected || home.selectedFolderId != folderId) return;
    await ref
        .read(homePerformanceControllerProvider.notifier)
        .load(folderId: folderId, localPremiumVerified: true, force: true);
  }

  Future<void> _selectOverviewRange(
    BuildContext context,
    HomeController controller,
    HomeChartRange range, {
    required AppPremiumState premiumState,
  }) async {
    if (range == HomeChartRange.oneYear) {
      final resolved = premiumState == AppPremiumState.unknown
          ? await _resolvePremiumForRestrictedAction()
          : premiumState;
      if (!context.mounted || resolved == AppPremiumState.unknown) return;
      if (resolved == AppPremiumState.free) {
        final result = await context.push<SubscriptionPaywallResult>(
          subscriptionSheetLocation,
        );
        if (!context.mounted || result == null) return;
        if (result == SubscriptionPaywallResult.premiumRestored) {
          showSubscriptionRestoreResult(
            context,
            type: SubscriptionRestoreResultType.premiumRestored,
          );
        } else {
          showPremiumUnlockedToast(context);
        }
      }
    }
    final selected = await controller.selectChartRange(range);
    if (!selected && context.mounted) showKandoTopFailureToast(context);
  }

  Future<AppPremiumState> _resolvePremiumForRestrictedAction() async {
    final current = ref.read(subscriptionControllerProvider).premiumState;
    if (current != AppPremiumState.unknown) return current;
    return ref
        .read(subscriptionControllerProvider.notifier)
        .refreshEntitlement();
  }

  Future<void> _loadPerformanceIfPremium(String folderId) async {
    final premiumState = await _resolvePremiumForRestrictedAction();
    if (!mounted || premiumState != AppPremiumState.premium) return;
    await ref
        .read(homePerformanceControllerProvider.notifier)
        .load(folderId: folderId, localPremiumVerified: true);
  }

  Future<void> _showCurrencySheet(BuildContext context, WidgetRef ref) {
    unawaited(ref.read(homeControllerProvider.notifier).preloadCurrencyRates());
    final selected = ref.read(homeControllerProvider).currencyCode;
    final pageContext = context;
    var query = '';

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KandoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final normalizedQuery = query.trim().toLowerCase();
            final currencies = AppCurrency.values.where((currency) {
              return normalizedQuery.isEmpty ||
                  currency.code.toLowerCase().contains(normalizedQuery) ||
                  currency.label.toLowerCase().contains(normalizedQuery) ||
                  currency.symbol.toLowerCase().contains(normalizedQuery);
            }).toList();
            return FractionallySizedBox(
              heightFactor: 0.88,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    20 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SheetDragHandle(),
                      const SizedBox(height: 16),
                      Text(
                        'Select currency',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: KandoColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('home-currency-search'),
                        onChanged: (value) {
                          setModalState(() => query = value);
                        },
                        style: const TextStyle(
                          color: KandoColors.text,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search currency...',
                          hintStyle: const TextStyle(
                            color: KandoColors.mutedText,
                            fontSize: 15,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: KandoColors.mutedText,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: KandoColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: KandoColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: KandoColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: KandoColors.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final currency in currencies) ...[
                                _CurrencyRow(
                                  code: currency.code,
                                  label: currency.label,
                                  symbol: currency.symbol,
                                  isSelected: currency.code == selected,
                                  onTap: () {
                                    final selection = ref
                                        .read(homeControllerProvider.notifier)
                                        .selectCurrency(currency.code);
                                    Navigator.of(context).pop();
                                    unawaited(
                                      selection.then((success) {
                                        if (!success && pageContext.mounted) {
                                          showKandoTopFailureToast(pageContext);
                                        }
                                      }),
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.currencyCode,
    required this.currencySymbol,
    required this.performanceSelected,
    required this.onOverviewPressed,
    required this.onPerformancePressed,
    required this.onCurrencyPressed,
  });

  final String currencyCode;
  final String currencySymbol;
  final bool performanceSelected;
  final VoidCallback onOverviewPressed;
  final VoidCallback onPerformancePressed;
  final VoidCallback onCurrencyPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: _HomeModeTabs(
              performanceSelected: performanceSelected,
              onOverviewPressed: onOverviewPressed,
              onPerformancePressed: onPerformancePressed,
            ),
          ),
          SizedBox(
            width: 98,
            height: 42,
            child: ClipRRect(
              key: const Key('home-currency-control'),
              borderRadius: BorderRadius.circular(9999),
              child: BackdropFilter(
                key: const Key('home-currency-blur'),
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: KandoColors.accentGlow10,
                  child: InkWell(
                    onTap: onCurrencyPressed,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                key: const Key('home-currency-icon'),
                                dimension: 16,
                                child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                    color: Color(0x33F0FE6F),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        currencySymbol,
                                        key: const Key('home-currency-symbol'),
                                        maxLines: 1,
                                        style: const TextStyle(
                                          color: KandoColors.accent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w400,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              SizedBox(
                                width: 34,
                                height: 24,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    currencyCode,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: KandoColors.accent,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                      height: 24 / 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 4),
                          const SizedBox.square(
                            dimension: 12,
                            child: OverflowBox(
                              maxWidth: 30,
                              maxHeight: 30,
                              child: Image(
                                key: Key('home-currency-chevron'),
                                image: AssetImage(
                                  'assets/home/currency_chevron.png',
                                ),
                                width: 30,
                                height: 30,
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
          ),
        ],
      ),
    );
  }
}

class _HomeModeTabs extends StatelessWidget {
  const _HomeModeTabs({
    required this.performanceSelected,
    required this.onOverviewPressed,
    required this.onPerformancePressed,
  });

  final bool performanceSelected;
  final VoidCallback onOverviewPressed;
  final VoidCallback onPerformancePressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desiredOverviewWidth = performanceSelected ? 69.0 : 92.0;
        final desiredPerformanceWidth = performanceSelected ? 115.0 : 92.0;
        const desiredTabsWidth = 194.0;
        final availableTabsWidth = (constraints.maxWidth - 40).clamp(
          0.0,
          desiredTabsWidth,
        );
        final widthScale = availableTabsWidth / desiredTabsWidth;

        return Row(
          children: [
            Container(
              key: const Key('home-mode-tabs'),
              width: availableTabsWidth,
              height: 42,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: KandoColors.borderFocus),
              ),
              child: Row(
                children: [
                  _HomeModeSegment(
                    key: const Key('home-overview-tab'),
                    width: desiredOverviewWidth * widthScale,
                    selected: !performanceSelected,
                    label: 'Overview',
                    onTap: onOverviewPressed,
                  ),
                  _HomeModeSegment(
                    key: const Key('home-performance-tab'),
                    width: desiredPerformanceWidth * widthScale,
                    selected: performanceSelected,
                    label: 'Performance',
                    onTap: onPerformancePressed,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const PremiumTopEntry(source: 'home'),
          ],
        );
      },
    );
  }
}

class _HomeModeSegment extends StatelessWidget {
  const _HomeModeSegment({
    super.key,
    required this.width,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final double width;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? KandoColors.primaryOnDefault
        : const Color(0xFF615D3B);
    return Material(
      color: selected ? KandoColors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(9999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9999),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: selected ? 9 : 8),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: selected ? 16 : 12,
                    fontWeight: FontWeight.w400,
                    height: selected ? 24 / 16 : 16 / 12,
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

class _PerformanceSection extends StatefulWidget {
  const _PerformanceSection({
    required this.state,
    required this.performance,
    required this.isPro,
    required this.onHidePressed,
    required this.onFolderPressed,
    required this.onRangeSelected,
    required this.onUnlock,
    required this.onRefresh,
  });

  final HomeState state;
  final HomePerformanceState performance;
  final bool isPro;
  final VoidCallback onHidePressed;
  final VoidCallback onFolderPressed;
  final ValueChanged<PerformanceRange> onRangeSelected;
  final VoidCallback onUnlock;
  final VoidCallback onRefresh;

  @override
  State<_PerformanceSection> createState() => _PerformanceSectionState();
}

class _PerformanceSectionState extends State<_PerformanceSection> {
  final _chartKey = GlobalKey<_InteractiveChartState>();
  final _infoLayerLink = LayerLink();
  OverlayEntry? _infoOverlay;

  @override
  void didUpdateWidget(covariant _PerformanceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.selectedFolderId != widget.state.selectedFolderId ||
        oldWidget.performance.selectedRange !=
            widget.performance.selectedRange) {
      _removeInfoTip();
      _chartKey.currentState?.clearSelection();
    }
  }

  @override
  void dispose() {
    _removeInfoTip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final performance = widget.performance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepaintBoundary(
          key: const Key('home-performance-header'),
          child: SizedBox(
            height: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Text(
                              'PERFORMANCE',
                              style: TextStyle(
                                color: KandoColors.text,
                                fontFamily: 'Fraunces',
                                fontSize: 24,
                                fontWeight: FontWeight.w400,
                                height: 32 / 24,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _AmountVisibilityButton(
                              key: const Key('home-performance-hide-amount'),
                              amountHidden: state.amountHidden,
                              onPressed: widget.onHidePressed,
                            ),
                          ],
                        ),
                      ),
                      _FolderPill(
                        key: const Key('home-performance-folder'),
                        label: state.selectedFolder.name,
                        onPressed: () {
                          _clearOverlays();
                          widget.onFolderPressed();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 20,
                  child: Row(
                    children: [
                      const Flexible(
                        fit: FlexFit.loose,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Cards with purchase price',
                            maxLines: 1,
                            style: TextStyle(
                              color: KandoColors.mutedText,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              height: 20 / 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Center(
                        child: CompositedTransformTarget(
                          link: _infoLayerLink,
                          child: TapRegion(
                            onTapOutside: (_) => _removeInfoTip(),
                            child: _PerformanceInfoButton(
                              key: const Key('home-performance-partial-info'),
                              onPressed: _toggleInfoTip,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (!widget.isPro)
          KandoPremiumLockedPanel(
            key: const Key('home-performance-locked'),
            title: 'Portfolio Performance',
            message:
                'Unlock total paid, profit and loss,\n'
                'return, longer\n'
                'history, and change explanations.',
            buttonLabel: 'Unlock Performance',
            buttonKey: const Key('home-unlock-performance'),
            onPressed: widget.onUnlock,
          )
        else if (performance.isFailure && performance.data == null)
          _FigmaFailurePanel(
            key: const Key('home-performance-failure'),
            height: 390,
            refreshKey: const Key('home-performance-refresh'),
            onRefresh: widget.onRefresh,
          )
        else if (performance.isLoading && performance.data == null)
          const SizedBox(
            key: Key('home-performance-loading'),
            height: 390,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (performance.data case final data?) ...[
          if (data.itemCount == 0)
            const SizedBox(
              key: Key('home-performance-empty'),
              height: 300,
              child: Center(child: Text('Your portfolio is empty.')),
            )
          else if (data.marketPriceStatus == MarketPriceStatus.missing)
            const SizedBox(
              key: Key('home-performance-no-data'),
              height: 300,
              child: Center(child: Text('No performance history available.')),
            )
          else ...[
            if (data.purchasePriceStatus == PurchasePriceStatus.missing)
              _PerformanceMetric(
                label: 'Market Value',
                value: _performanceAmount(state, data.current.marketValueUsd),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _PerformanceMetric(
                      label: 'Total Paid',
                      value: _performanceAmount(
                        state,
                        data.current.totalPaidUsd,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PerformanceMetric(
                      label: 'Market Value',
                      value: _performanceAmount(
                        state,
                        data.current.marketValueUsd,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PerformanceMetric(
                      label: 'Profit / Loss',
                      value: _performanceAmount(
                        state,
                        data.current.profitLossUsd,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _PerformanceMetric(
                      label: 'Return',
                      value: data.current.returnPercent == null
                          ? '--'
                          : '${data.current.returnPercent!.toStringAsFixed(2)}%',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              height: 190,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: KandoColors.borderSubtle),
                color: KandoColors.ink.withValues(alpha: 0.55),
              ),
              child: Column(
                children: [
                  _PerformanceRangePicker(
                    selected: performance.selectedRange,
                    onSelected: (range) {
                      _clearOverlays();
                      widget.onRangeSelected(range);
                    },
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _InteractiveChart(
                      key: _chartKey,
                      semanticKey: const Key('home-performance-chart'),
                      semanticLabel: 'Portfolio performance chart',
                      persistentSelection: true,
                      onSelectionChanged: (selected) {
                        if (selected) _removeInfoTip();
                      },
                      values: data.series
                          .map((point) => point.marketValueUsd)
                          .toList(),
                      dates: data.series.map((point) => point.date).toList(),
                      quantities: data.series
                          .map((point) => point.quantity)
                          .toList(),
                      formattedValues: data.series
                          .map(
                            (point) =>
                                _performanceAmount(state, point.marketValueUsd),
                          )
                          .toList(),
                      tooltipRows: [
                        for (var index = 0; index < data.series.length; index++)
                          _performanceTooltipRows(state, data.series, index),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (data.purchasePriceStatus == PurchasePriceStatus.missing)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Add purchase prices to track profit and return.'),
              ),
          ],
        ],
      ],
    );
  }

  void _clearOverlays() {
    _removeInfoTip();
    _chartKey.currentState?.clearSelection();
  }

  void _toggleInfoTip() {
    if (_infoOverlay != null) {
      _removeInfoTip();
      return;
    }
    _chartKey.currentState?.clearSelection();
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: Stack(
            children: [
              CompositedTransformFollower(
                link: _infoLayerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topCenter,
                followerAnchor: Alignment.bottomCenter,
                offset: const Offset(0, -3),
                child: const Material(
                  color: Colors.transparent,
                  child: _PerformanceInfoTip(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _infoOverlay = entry;
    overlay.insert(entry);
  }

  void _removeInfoTip() {
    _infoOverlay?.remove();
    _infoOverlay = null;
  }
}

class _PerformanceInfoButton extends StatelessWidget {
  const _PerformanceInfoButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Purchase price coverage',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 13,
          height: 13,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: KandoColors.accent.withValues(alpha: .6),
              width: .5,
            ),
          ),
          child: SvgPicture.asset(
            'assets/home/performance_info.svg',
            key: const Key('home-performance-info-icon'),
            width: 13,
            height: 13,
          ),
        ),
      ),
    );
  }
}

class _PerformanceInfoTip extends StatelessWidget {
  const _PerformanceInfoTip();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('home-performance-info-tip'),
      child: SizedBox(
        width: 242,
        height: 53.5,
        child: Column(
          children: [
            Container(
              width: 242,
              height: 46,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    offset: Offset(0, 4),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: .8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  child: Text(
                    'Profit and return are calculated only from cards\n'
                    'with purchase prices',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      height: 14 / 10,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 19,
              height: 7.5,
              child: Align(
                alignment: Alignment.topCenter,
                child: SvgPicture.asset(
                  'assets/home/performance_tooltip_notch.svg',
                  key: const Key('home-performance-info-notch'),
                  width: 19,
                  height: 6.70087,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _performanceTooltipRows(
  HomeState state,
  List<PerformancePointDto> points,
  int index,
) {
  final point = points[index];
  final quantityDelta = point.quantityChange;
  return [
    if (point.marketChangeUsd != null)
      'Market: ${_performanceChange(state, point.marketChangeUsd!)}',
    if (point.portfolioChangeUsd != null)
      'Portfolio: ${_performanceChange(state, point.portfolioChangeUsd!)}',
    'Qty: ${point.quantity}${quantityDelta == null || quantityDelta == 0 ? '' : ' (${quantityDelta > 0 ? '+' : ''}$quantityDelta)'}',
  ];
}

String _performanceChange(HomeState state, double value) {
  final formatted = _performanceAmount(state, value);
  if (state.amountHidden || value <= 0) return formatted;
  return '+$formatted';
}

String _performanceAmount(HomeState state, double? value) {
  if (value == null) return '--';
  return CurrencyFormatter(
    currency: state.currency,
  ).formatUsd(value, hidden: state.amountHidden);
}

class _PerformanceRangePicker extends StatelessWidget {
  const _PerformanceRangePicker({
    required this.selected,
    required this.onSelected,
  });

  final PerformanceRange selected;
  final ValueChanged<PerformanceRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          for (final range in PerformanceRange.values)
            Expanded(
              child: InkWell(
                key: Key('home-performance-range-${range.apiValue}'),
                onTap: () => onSelected(range),
                child: Center(
                  child: Text(
                    range.apiValue,
                    style: TextStyle(
                      color: range == selected
                          ? KandoColors.accent
                          : KandoColors.mutedText,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PerformanceMetric extends StatelessWidget {
  const _PerformanceMetric({required this.label, required this.value});

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

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({
    required this.state,
    required this.showOneYearProBadge,
    required this.onFolderPressed,
    required this.onHidePressed,
    required this.onRangeSelected,
    required this.onRefresh,
  });

  final HomeState state;
  final bool showOneYearProBadge;
  final VoidCallback onFolderPressed;
  final VoidCallback onHidePressed;
  final ValueChanged<HomeChartRange> onRangeSelected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final chartValues = state.chartValues;
    final showEmptyState = !state.isUnavailable && !state.hasCollectionItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: const Text(
            'PORTFOLIO',
            style: TextStyle(
              color: Color(0xFF92927D),
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 24 / 16,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        state.totalAmountText,
                        style: const TextStyle(
                          color: KandoColors.accent,
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                          height: 44 / 36,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _AmountVisibilityButton(
                    key: const Key('home-hide-amount'),
                    amountHidden: state.amountHidden,
                    onPressed: onHidePressed,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _FolderPill(
              label: state.selectedFolder.name,
              onPressed: onFolderPressed,
            ),
          ],
        ),
        SizedBox(height: showEmptyState ? 24 : 8),
        if (state.isUnavailable)
          _FigmaFailurePanel(
            key: const Key('home-failure-chart'),
            height: 306,
            refreshKey: const Key('home-failure-chart-refresh'),
            onRefresh: onRefresh,
          )
        else if (showEmptyState)
          _PortfolioEmptyPanel(
            onScan: () => context.go('/scan'),
            onSearch: () => context.go('/search'),
          )
        else if (state.isMarketPriceMissing)
          const _EmptyCardBlock(
            key: Key('home-portfolio-market-price-missing'),
            message: 'Market price unavailable',
          )
        else
          SizedBox(
            height: 203,
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 13, 13, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x1FFFFFFF)),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1F747B26), Color(0x0A141506)],
                ),
              ),
              child: Column(
                children: [
                  _ChartRangePicker(
                    selected: state.chartRange,
                    showOneYearProBadge: showOneYearProBadge,
                    onSelected: onRangeSelected,
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: _InteractiveChart(
                      values: chartValues,
                      dates: state.chartDates,
                      formattedValues: chartValues
                          .map(state.formatCardPrice)
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AmountVisibilityButton extends StatelessWidget {
  const _AmountVisibilityButton({
    super.key,
    required this.amountHidden,
    required this.onPressed,
  });

  final bool amountHidden;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: amountHidden ? 'Show portfolio amount' : 'Hide portfolio amount',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF464835)),
          ),
          child: Icon(
            amountHidden
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 14,
            color: KandoColors.accent,
          ),
        ),
      ),
    );
  }
}

class _FolderPill extends StatelessWidget {
  const _FolderPill({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      height: 24,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0x0DF0FE6F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x99F0FE6F), width: .5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: Center(
                  child: SvgPicture.asset(
                    'assets/home/folder_switch.svg',
                    width: 10.5,
                    height: 8.24644,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: KandoColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 16 / 13,
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

class _ChartRangePicker extends StatelessWidget {
  const _ChartRangePicker({
    required this.selected,
    required this.showOneYearProBadge,
    required this.onSelected,
  });

  final HomeChartRange selected;
  final bool showOneYearProBadge;
  final ValueChanged<HomeChartRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: KandoColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          children: [
            for (final range in HomeChartRange.values)
              if (showOneYearProBadge && range == HomeChartRange.oneYear)
                SizedBox(width: 70, child: _rangeOption(range))
              else
                Expanded(child: _rangeOption(range)),
          ],
        ),
      ),
    );
  }

  Widget _rangeOption(HomeChartRange range) {
    return GestureDetector(
      key: Key('home-chart-range-${range.label}'),
      onTap: () => onSelected(range),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: range == selected
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99747B26), Color(0x33747B26)],
                )
              : null,
          boxShadow: range == selected
              ? const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              range.label.toUpperCase(),
              style: TextStyle(
                color: range == selected
                    ? KandoColors.accent
                    : const Color(0xFF92927D),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 16 / 13,
              ),
            ),
            if (showOneYearProBadge && range == HomeChartRange.oneYear) ...[
              const SizedBox(width: 4),
              Container(
                key: const Key('home-chart-range-1y-pro-badge'),
                width: 35,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: KandoColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    color: KandoColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 18 / 12,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PortfolioEmptyPanel extends StatelessWidget {
  const _PortfolioEmptyPanel({required this.onScan, required this.onSearch});

  final VoidCallback onScan;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 410,
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 25),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14FFFFFF)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x1F747B26), Color(0x0A141506)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const _FigmaEmptyStateIllustration(
                key: Key('home-portfolio-empty-illustration'),
              ),
              const SizedBox(height: 24),
              const Column(
                children: [
                  Text(
                    'Add your first card',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: KandoColors.text,
                      fontFamily: 'Fraunces',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 20 / 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Start tracking your collection's\nvalue,price trends, and top cards.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: KandoColors.mutedText,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      height: 24 / 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Column(
                children: [
                  _FigmaEmptyActionButton(
                    key: const Key('home-portfolio-empty-scan'),
                    iconAssetPath: 'assets/home/empty_action_camera.svg',
                    iconSize: const Size(16.0417, 14.5417),
                    label: 'Scan Cards',
                    isPrimary: true,
                    onPressed: onScan,
                  ),
                  const SizedBox(height: 12),
                  _FigmaEmptyActionButton(
                    key: const Key('home-portfolio-empty-search'),
                    iconAssetPath: 'assets/home/empty_action_search.svg',
                    iconSize: const Size(15.2707, 15.8891),
                    label: 'Search Cards',
                    onPressed: onSearch,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FigmaEmptyActionButton extends StatelessWidget {
  const _FigmaEmptyActionButton({
    super.key,
    required this.iconAssetPath,
    required this.iconSize,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String iconAssetPath;
  final Size iconSize;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final foreground = isPrimary
        ? KandoColors.primaryOnDefault
        : KandoColors.text;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 36,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isPrimary ? KandoColors.accent : KandoColors.elevatedSurface,
            borderRadius: BorderRadius.circular(99),
            border: isPrimary
                ? null
                : Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Center(
                  child: SvgPicture.asset(
                    iconAssetPath,
                    width: iconSize.width,
                    height: iconSize.height,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 16 / 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FigmaFailurePanel extends StatelessWidget {
  const _FigmaFailurePanel({
    super.key,
    required this.height,
    required this.refreshKey,
    required this.onRefresh,
  });

  final double height;
  final Key refreshKey;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14FFFFFF)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x1F747B26), Color(0x0A141506)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _FigmaFailureStateIllustration(),
            const SizedBox(height: 24),
            const Text(
              noContentAvailableText,
              style: TextStyle(
                color: KandoColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 24 / 16,
              ),
            ),
            const SizedBox(height: 24),
            _FigmaRefreshButton(key: refreshKey, onPressed: onRefresh),
          ],
        ),
      ),
    );
  }
}

class _FigmaEmptyStateIllustration extends StatelessWidget {
  const _FigmaEmptyStateIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        children: [
          Positioned(
            left: 4.96,
            top: 8.94,
            child: SvgPicture.asset(
              'assets/home/empty_state_magnifier_outer.svg',
              key: const Key('home-empty-magnifier-outer'),
              width: 89.04,
              height: 79.08,
              excludeFromSemantics: true,
            ),
          ),
          Positioned(
            left: 29,
            top: 32.37,
            child: SvgPicture.asset(
              'assets/home/empty_state_magnifier_inner.svg',
              key: const Key('home-empty-magnifier-inner'),
              width: 27.1,
              height: 29.61,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaFailureStateIllustration extends StatelessWidget {
  const _FigmaFailureStateIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        children: [
          Positioned(
            left: 2.11,
            top: 9.73,
            child: SvgPicture.asset(
              'assets/home/failure_state_error.svg',
              key: const Key('home-failure-error-icon'),
              width: 91.89,
              height: 79.83,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaRefreshButton extends StatelessWidget {
  const _FigmaRefreshButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: refreshText,
      excludeSemantics: true,
      child: SizedBox(
        width: 122,
        height: 36,
        child: Material(
          color: KandoColors.accent,
          borderRadius: BorderRadius.circular(99),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(99),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/home/refresh.svg',
                      key: const Key('home-failure-refresh-icon'),
                      width: 16,
                      height: 16,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Refresh',
                      style: TextStyle(
                        color: KandoColors.primaryOnDefault,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 20 / 14,
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

class _MostValuableSection extends StatelessWidget {
  const _MostValuableSection({
    required this.state,
    required this.onRefresh,
    required this.onViewAll,
  });

  final HomeState state;
  final VoidCallback onRefresh;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final cards = state.mostValuableCards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Most Valuable',
          isUnavailable: state.isUnavailable,
          useShortViewLabel: !state.hasCollectionItems,
          viewAllKey: const Key('home-most-valuable-view-all'),
          onViewAll: onViewAll,
        ),
        const SizedBox(height: 16),
        if (state.isUnavailable)
          _FigmaFailurePanel(
            key: const Key('home-failure-most-valuable'),
            height: 256,
            refreshKey: const Key('home-failure-most-valuable-refresh'),
            onRefresh: onRefresh,
          )
        else if (state.isMarketPriceMissing)
          const _EmptyCardBlock(
            key: Key('home-most-valuable-market-price-missing'),
            message: 'Market price unavailable',
          )
        else if (cards.isEmpty)
          const _EmptyCardBlock(message: 'No cards in this portfolio yet')
        else
          SizedBox(
            height: 281,
            child: ListView.separated(
              key: const Key('home-most-valuable-list'),
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final card = cards[index];
                return _MostValuableTile(
                  key: Key(
                    'home-most-valuable-card-${state.selectedFolder.id}-$index',
                  ),
                  card: card,
                  onTap: card.cardRef == null
                      ? null
                      : () => context.push(
                          '/cards/${card.cardRef}?collection=portfolio&entry=edit',
                        ),
                  price: state.formatCardPrice(card.priceUsd),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TrendingSection extends StatelessWidget {
  const _TrendingSection({
    required this.state,
    required this.onRefresh,
    required this.onViewAll,
  });

  final HomeState state;
  final VoidCallback onRefresh;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final trends = state.dashboard.trending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Trending Today',
          isUnavailable:
              state.isUnavailable || state.dashboard.trendingUnavailable,
          viewAllKey: const Key('home-trending-view-all'),
          onViewAll: onViewAll,
        ),
        const SizedBox(height: 16),
        if (!state.isUnavailable &&
            state.trendingStatus == KandoLoadStatus.loading)
          const SizedBox(
            key: Key('home-loading-trending'),
            height: 256,
            child: KandoLoadingBlock(),
          )
        else if (!state.isUnavailable &&
            (state.trendingStatus == KandoLoadStatus.failure ||
                state.dashboard.trendingUnavailable))
          _FigmaFailurePanel(
            key: const Key('home-failure-trending'),
            height: 256,
            refreshKey: const Key('home-failure-trending-refresh'),
            onRefresh: onRefresh,
          )
        else if (trends.isEmpty)
          const _EmptyCardBlock(message: 'No trending cards available')
        else
          for (var index = 0; index < trends.length; index += 1) ...[
            _TrendingRow(
              title: trends[index].title,
              subtitle: trends[index].subtitle,
              price: state.formatCardPrice(trends[index].priceUsd),
              percent: MarketChange.fromPercent(
                trends[index].increaseRate,
              ).percentText,
              percentColor: marketChangeTextColor(
                MarketChange.fromPercent(
                  trends[index].increaseRate,
                ).percentText,
              ),
              imageAssetPath: trends[index].imageAssetPath,
              imageUrl: trends[index].imageUrl,
              onTap: trends[index].cardRef == null
                  ? null
                  : () => context.push(
                      '/cards/${trends[index].cardRef}?collection=normal&entry=trending%20today',
                    ),
              showPlaceholder: state.isUnavailable,
              placeholderKey: state.isUnavailable
                  ? Key('home-failure-trend-placeholder-$index')
                  : null,
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.viewAllKey,
    required this.onViewAll,
    this.isUnavailable = false,
    this.useShortViewLabel = false,
  });

  final String title;
  final Key viewAllKey;
  final VoidCallback onViewAll;
  final bool isUnavailable;
  final bool useShortViewLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                style: const TextStyle(
                  color: KandoColors.text,
                  fontFamily: 'Fraunces',
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  height: 32 / 24,
                  fontVariations: [
                    FontVariation('SOFT', 0),
                    FontVariation('WONK', 1),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (isUnavailable)
          const Text(
            'View',
            style: TextStyle(
              color: Color(0xFF2C3400),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 16 / 13,
            ),
          )
        else
          SizedBox(
            width: 60,
            child: InkWell(
              key: viewAllKey,
              onTap: onViewAll,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: useShortViewLabel
                      ? const Text(
                          'View',
                          style: TextStyle(
                            color: Color(0xFF2C3400),
                            fontWeight: FontWeight.w400,
                            fontSize: 13,
                            height: 16 / 13,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'View all',
                              style: TextStyle(
                                color: KandoColors.accent,
                                fontWeight: FontWeight.w400,
                                fontSize: 16,
                                height: 20 / 16,
                              ),
                            ),
                            const SizedBox(width: 4),
                            SvgPicture.asset(
                              'assets/home/view_all_arrow.svg',
                              key: const Key('home-view-all-arrow'),
                              width: 14,
                              height: 10,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MostValuableTile extends StatelessWidget {
  const _MostValuableTile({
    super.key,
    required this.card,
    required this.price,
    required this.onTap,
  });

  final HomeCardHighlight card;
  final String price;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final percent = MarketChange.fromPercent(card.increasePercent).percentText;
    final percentColor = marketChangeTextColor(percent);

    return SizedBox(
      width: 144,
      height: 281,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x1FFFFFFF)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xCC1C1E15), Color(0xE612140D)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                offset: Offset(0, 4),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 155,
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: KandoColors.ink,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: _HomeCardImage(
                            imageAssetPath: card.imageAssetPath,
                            imageUrl: card.imageUrl,
                            height: 143,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: -2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: KandoColors.accentGlow10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              percent,
                              style: TextStyle(
                                color: percentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                height: 14 / 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE4E3D3),
                  fontFamily: 'Fraunces',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 20 / 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                card.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KandoColors.mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  height: 18 / 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFF6AF),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 24 / 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendingRow extends StatelessWidget {
  const _TrendingRow({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.percent,
    required this.percentColor,
    required this.imageAssetPath,
    required this.imageUrl,
    required this.onTap,
    required this.showPlaceholder,
    this.placeholderKey,
  });

  final String title;
  final String subtitle;
  final String price;
  final String percent;
  final Color percentColor;
  final String? imageAssetPath;
  final String? imageUrl;
  final VoidCallback? onTap;
  final bool showPlaceholder;
  final Key? placeholderKey;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 17),
        child: Row(
          children: [
            if (showPlaceholder)
              SizedBox(
                width: 42,
                height: 58,
                child: KandoCardImage(
                  imageUrl: null,
                  placeholderKey: placeholderKey,
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 42,
                  height: 58,
                  child: _HomeCardImage(
                    imageAssetPath: imageAssetPath,
                    imageUrl: imageUrl,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE4E3D3),
                      fontFamily: 'Fraunces',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 20 / 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KandoColors.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      height: 18 / 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFF6AF),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 20 / 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  percent,
                  style: TextStyle(
                    color: percentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCardImage extends StatelessWidget {
  const _HomeCardImage({
    required this.imageAssetPath,
    required this.imageUrl,
    this.height,
  });

  final String? imageAssetPath;
  final String? imageUrl;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null) {
      return KandoCardImage(
        imageUrl: url,
        height: height,
        fit: BoxFit.contain,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        filterQuality: FilterQuality.high,
      );
    }
    final asset = imageAssetPath;
    if (asset != null) {
      return Image.asset(
        asset,
        height: height,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => const KandoCardImage(imageUrl: null),
      );
    }
    return const KandoCardImage(imageUrl: null);
  }
}

class _EmptyCardBlock extends StatelessWidget {
  const _EmptyCardBlock({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14FFFFFF)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x1F747B26), Color(0x0A141506)],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const _FigmaEmptyStateIllustration(
              key: Key('home-card-empty-illustration'),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KandoColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 24 / 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetDragHandle extends StatelessWidget {
  const _SheetDragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: KandoColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({
    required this.code,
    required this.label,
    required this.symbol,
    required this.isSelected,
    required this.onTap,
  });

  final String code;
  final String label;
  final String symbol;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: KandoColors.elevatedSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? KandoColors.accent : KandoColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? KandoColors.accent : KandoColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: KandoColors.border),
              ),
              child: Text(
                symbol,
                style: TextStyle(
                  color: isSelected ? KandoColors.ink : KandoColors.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      color: KandoColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      color: KandoColors.mutedText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color: isSelected ? KandoColors.accent : KandoColors.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveChart extends StatefulWidget {
  const _InteractiveChart({
    super.key,
    required this.values,
    required this.dates,
    required this.formattedValues,
    this.quantities = const [],
    this.semanticKey = const Key('home-portfolio-chart'),
    this.semanticLabel = 'Portfolio value chart',
    this.tooltipRows,
    this.persistentSelection = false,
    this.onSelectionChanged,
  });

  final List<double> values;
  final List<String> dates;
  final List<String> formattedValues;
  final List<int> quantities;
  final Key semanticKey;
  final String semanticLabel;
  final List<List<String>>? tooltipRows;
  final bool persistentSelection;
  final ValueChanged<bool>? onSelectionChanged;

  @override
  State<_InteractiveChart> createState() => _InteractiveChartState();
}

class _InteractiveChartState extends State<_InteractiveChart> {
  int? _selectedIndex;

  String get _semanticValue {
    if (widget.values.isEmpty) return 'No chart data';
    final selectedIndex = _selectedIndex;
    if (selectedIndex == null) return 'No chart point selected';
    final index = selectedIndex.clamp(0, widget.values.length - 1);
    final rows =
        widget.tooltipRows?[index] ??
        [
          'Price: ${_chartPrice(widget.formattedValues, index)}',
          if (index < widget.quantities.length)
            'Qty: ${widget.quantities[index]}',
        ];
    return [
      'Date: ${_formatChartDate(widget.dates, index)}',
      ...rows,
    ].join(', ');
  }

  @override
  void didUpdateWidget(covariant _InteractiveChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.values != widget.values || oldWidget.dates != widget.dates) {
      _selectedIndex = null;
    }
  }

  void _selectAt(double localX, double width) {
    if (widget.values.isEmpty || width <= 0) return;
    final normalizedX = (localX / width).clamp(0.0, 1.0);
    final index = widget.values.length == 1
        ? 0
        : (normalizedX * (widget.values.length - 1)).round();
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    widget.onSelectionChanged?.call(true);
  }

  void clearSelection() {
    if (_selectedIndex == null) return;
    setState(() => _selectedIndex = null);
    widget.onSelectionChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          key: widget.semanticKey,
          label: widget.semanticLabel,
          value: _semanticValue,
          child: MouseRegion(
            onHover: (event) => _selectAt(event.localPosition.dx, width),
            onExit: (_) {
              if (!widget.persistentSelection) clearSelection();
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) =>
                  _selectAt(event.localPosition.dx, width),
              onPointerMove: (event) =>
                  _selectAt(event.localPosition.dx, width),
              onPointerUp: (_) {
                if (!widget.persistentSelection) clearSelection();
              },
              onPointerCancel: (_) {
                if (!widget.persistentSelection) clearSelection();
              },
              child: CustomPaint(
                painter: _ChartPainter(
                  values: widget.values,
                  dates: widget.dates,
                  formattedValues: widget.formattedValues,
                  tooltipRows: widget.tooltipRows,
                  selectedIndex: _selectedIndex,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter({
    required this.values,
    required this.dates,
    required this.formattedValues,
    required this.tooltipRows,
    required this.selectedIndex,
  });

  final List<double> values;
  final List<String> dates;
  final List<String> formattedValues;
  final List<List<String>>? tooltipRows;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = KandoColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final gridPaint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;

    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(
        Offset.zero + Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    if (values.isEmpty) {
      return;
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;
    final points = <Offset>[];
    const topInset = 18.0;
    const bottomInset = 6.0;
    final availableHeight = size.height - topInset - bottomInset;

    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * index / (values.length - 1);
      final normalized = range == 0 ? 0.5 : (values[index] - minValue) / range;
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

    if (values.length > 1) {
      final areaPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final areaPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KandoColors.accent.withValues(alpha: 0.2),
            KandoColors.accent.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size);
      canvas.drawPath(areaPath, areaPaint);
      canvas.drawPath(path, linePaint);
    }

    final selectedIndex = this.selectedIndex;
    if (selectedIndex == null) return;
    final resolvedSelectedIndex = selectedIndex
        .clamp(0, points.length - 1)
        .toInt();
    final selected = points[resolvedSelectedIndex];
    final xAxisY = size.height - bottomInset;
    _drawDashedLine(
      canvas,
      Offset(selected.dx, 0),
      Offset(selected.dx, xAxisY),
      Paint()
        ..color = KandoColors.accent.withValues(alpha: 0.7)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      selected,
      6,
      Paint()..color = KandoColors.accent.withValues(alpha: 0.2),
    );
    canvas.drawCircle(selected, 3, Paint()..color = KandoColors.accent);

    final datePainter = TextPainter(
      text: TextSpan(
        text: 'Date: ${_formatChartDate(dates, resolvedSelectedIndex)}',
        style: const TextStyle(
          color: Color(0xFF92927D),
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 16 / 11,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final rowPainters =
        (tooltipRows?[resolvedSelectedIndex] ??
                ['Price: ${_chartPrice(formattedValues, resolvedSelectedIndex)}'])
            .map(
              (row) => TextPainter(
                text: TextSpan(
                  text: row,
                  style: const TextStyle(
                    color: KandoColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 16 / 11,
                  ),
                ),
                maxLines: 1,
                textDirection: TextDirection.ltr,
              )..layout(),
            )
            .toList();
    final tooltipSize = Size(
      [
            datePainter.width,
            ...rowPainters.map((painter) => painter.width),
          ].reduce(math.max) +
          16,
      16.0 * (rowPainters.length + 1) + 12,
    );
    final preferredLeft = selected.dx + tooltipSize.width + 12 <= size.width
        ? selected.dx + 12
        : selected.dx - tooltipSize.width - 12;
    final tooltipLeft = preferredLeft
        .clamp(0.0, size.width - tooltipSize.width)
        .toDouble();
    final preferredTop = selected.dy - tooltipSize.height - 8 >= 0
        ? selected.dy - tooltipSize.height - 8
        : selected.dy + 8;
    final tooltipTop = preferredTop
        .clamp(0.0, size.height - tooltipSize.height)
        .toDouble();
    final tooltipRect = Rect.fromLTWH(
      tooltipLeft,
      tooltipTop,
      tooltipSize.width,
      tooltipSize.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tooltipRect, const Radius.circular(6)),
      Paint()..color = const Color(0xE61A1C14),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tooltipRect, const Radius.circular(6)),
      Paint()
        ..color = const Color(0x99F0FE6F)
        ..style = PaintingStyle.stroke,
    );
    datePainter.paint(canvas, tooltipRect.topLeft + const Offset(8, 8));
    for (var index = 0; index < rowPainters.length; index++) {
      rowPainters[index].paint(
        canvas,
        tooltipRect.topLeft + Offset(8, 8 + 16.0 * (index + 1)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.dates != dates ||
        oldDelegate.formattedValues != formattedValues ||
        oldDelegate.tooltipRows != tooltipRows ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}

void _drawDashedLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Paint paint, {
  double dash = 4,
  double gap = 4,
}) {
  final distance = (end - start).distance;
  if (distance <= 0) return;
  final direction = (end - start) / distance;
  var traveled = 0.0;
  while (traveled < distance) {
    final segmentStart = start + direction * traveled;
    final segmentEnd = start + direction * math.min(traveled + dash, distance);
    canvas.drawLine(segmentStart, segmentEnd, paint);
    traveled += dash + gap;
  }
}

String _formatChartDate(List<String> dates, int index) {
  if (index >= dates.length) return '--';
  final value = DateTime.tryParse(dates[index]);
  if (value == null) return dates[index].isEmpty ? '--' : dates[index];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _chartPrice(List<String> formattedValues, int index) {
  return index < formattedValues.length ? formattedValues[index] : '--';
}
