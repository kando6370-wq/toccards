import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/card_detail/card_detail_models.dart';
import '../features/card_detail/card_detail_page.dart';
import '../features/collection/collection_page.dart';
import '../features/home/home_page.dart';
import '../features/home/trending_today_page.dart';
import '../features/onboarding/onboarding_gate.dart';
import '../features/profile/account_page.dart';
import '../features/profile/api_request_log_page.dart';
import '../features/profile/customer_support_page.dart';
import '../features/profile/profile_page.dart';
import '../features/scan/scan_page.dart';
import '../features/search/search_page.dart';
import '../features/search/set_detail_page.dart';
import '../features/subscription/subscription_controller.dart';
import '../features/subscription/subscription_page.dart';
import '../features/subscription/subscription_route_page.dart';
import '../features/subscription/startup_subscription_gate.dart';
import '../shared/analytics/analytics_events.dart';
import '../shared/analytics/app_analytics.dart';
import '../shared/ui/app_shell.dart';
import '../shared/ui/kando_bottom_sheet_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          const home = AnalyticsPageView(
            event: AnalyticsEvent.homeView,
            child: HomePage(),
          );
          return const OnboardingGate(
            home: StartupSubscriptionGate(source: 'cold_start', home: home),
            firstLaunchHome: StartupSubscriptionGate(
              source: 'onboarding',
              home: home,
            ),
          );
        },
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => _mainTabPage(
          context,
          state,
          KandoMainTab.home,
          const AnalyticsPageView(
            event: AnalyticsEvent.homeView,
            child: HomePage(),
          ),
        ),
      ),
      GoRoute(
        path: '/trending',
        builder: (context, state) => const TrendingTodayPage(),
      ),
      GoRoute(
        path: '/collection',
        pageBuilder: (context, state) => _mainTabPage(
          context,
          state,
          KandoMainTab.collection,
          const CollectionPage(),
        ),
      ),
      GoRoute(
        path: '/scan',
        pageBuilder: (context, state) => _mainTabPage(
          context,
          state,
          KandoMainTab.scan,
          const AnalyticsPageView(
            event: AnalyticsEvent.scanView,
            child: ScanPage(),
          ),
        ),
      ),
      GoRoute(
        path: '/cards/:cardId',
        builder: (context, state) {
          final cardId = state.pathParameters['cardId'] ?? '';
          final extra = state.extra;
          final preview = extra is CardDetailPreview && extra.cardId == cardId
              ? extra
              : null;
          final collectionType =
              state.uri.queryParameters['collection'] ??
              AnalyticsValue.collectionNormal;
          return CardDetailPage(
            cardId: cardId,
            preview: preview,
            collectionItemId: state.uri.queryParameters['item_id'],
            collectionType: collectionType,
            entrySource:
                state.uri.queryParameters['entry'] ??
                AnalyticsValue.sourceSearch,
          );
        },
      ),
      GoRoute(
        path: '/collection-items/pending',
        pageBuilder: (context, state) => KandoBottomSheetPage<void>(
          key: state.pageKey,
          barrierColor: const Color(0xB8000000),
          isDismissible: true,
          heightFactor: 0.93,
          child: const QuickCollectionReviewPage(heightFactor: 1),
        ),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) => _mainTabPage(
          context,
          state,
          KandoMainTab.search,
          SearchPage(fromScan: state.uri.queryParameters['from'] == 'scan'),
        ),
      ),
      GoRoute(
        path: '/sets/:setId',
        builder: (context, state) => SetDetailPage(
          setId: state.pathParameters['setId'] ?? '',
          game: state.uri.queryParameters['game'] ?? '',
          setName: state.uri.queryParameters['name'] ?? '',
        ),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) => _mainTabPage(
          context,
          state,
          KandoMainTab.profile,
          const AnalyticsPageView(
            event: AnalyticsEvent.profileView,
            child: ProfilePage(),
          ),
        ),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountPage(),
      ),
      GoRoute(
        path: '/customer-support',
        builder: (context, state) => const AnalyticsPageView(
          event: AnalyticsEvent.supportView,
          child: CustomerSupportPage(),
        ),
      ),
      GoRoute(
        path: '/profile/api-requests',
        builder: (context, state) => const ApiRequestLogPage(),
      ),
      GoRoute(
        path: '/subscription',
        pageBuilder: (context, state) {
          final sheet = state.uri.queryParameters['presentation'] == 'sheet';
          final source = state.uri.queryParameters['source'];
          final entrySource = state.uri.queryParameters['entry_source'];
          final analyticsScene = state.uri.queryParameters['scene'];
          if (sheet) {
            return KandoBottomSheetPage<SubscriptionPaywallResult>(
              key: state.pageKey,
              barrierColor: const Color(0x99000000),
              isDismissible: false,
              useSafeArea: true,
              heightFactor: subscriptionSheetHeightFactor,
              sheetAnimationStyle: subscriptionSheetAnimationStyle,
              child: SubscriptionPage(
                sheet: true,
                source: source,
                entrySource: entrySource,
                analyticsScene: analyticsScene,
              ),
            );
          }
          return KandoSubscriptionPage<SubscriptionPaywallResult>(
            key: state.pageKey,
            source: source,
            child: SubscriptionPage(
              sheet: false,
              source: source,
              entrySource: entrySource,
              analyticsScene: analyticsScene,
            ),
          );
        },
      ),
      GoRoute(
        path: '/subscription/success',
        builder: (context, state) => SubscriptionSuccessPage(
          source: state.uri.queryParameters['source'],
          entrySource: state.uri.queryParameters['entry_source'],
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

Page<void> _mainTabPage(
  BuildContext context,
  GoRouterState state,
  KandoMainTab currentTab,
  Widget child,
) {
  final transition = state.extra;
  if (transition is! KandoMainTabTransition ||
      transition.to != currentTab ||
      transition.from == currentTab) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }
  return KandoMainTabPage(
    key: state.pageKey,
    transition: transition,
    duration: _platformPageTransitionDuration(context),
    child: child,
  );
}

Duration _platformPageTransitionDuration(BuildContext context) {
  final theme = Theme.of(context);
  final transitionBuilder = theme.pageTransitionsTheme.builders[theme.platform];
  return transitionBuilder?.transitionDuration ??
      const Duration(milliseconds: 300);
}
