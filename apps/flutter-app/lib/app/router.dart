import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../features/subscription/subscription_page.dart';
import '../shared/analytics/analytics_events.dart';
import '../shared/analytics/app_analytics.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          return const OnboardingGate(
            home: AnalyticsPageView(
              event: AnalyticsEvent.homeView,
              child: HomePage(),
            ),
          );
        },
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => _mainTabPage(
          state,
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
        pageBuilder: (context, state) =>
            _mainTabPage(state, const CollectionPage()),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const AnalyticsPageView(
          event: AnalyticsEvent.scanView,
          child: ScanPage(),
        ),
      ),
      GoRoute(
        path: '/cards/:cardId',
        builder: (context, state) {
          final collectionType =
              state.uri.queryParameters['collection'] ??
              AnalyticsValue.collectionNormal;
          return CardDetailPage(
            cardId: state.pathParameters['cardId'] ?? '',
            collectionType: collectionType,
            entrySource:
                state.uri.queryParameters['entry'] ??
                AnalyticsValue.sourceSearch,
          );
        },
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) => _mainTabPage(
          state,
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
          state,
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
          return CustomTransitionPage<void>(
            key: state.pageKey,
            opaque: !sheet,
            barrierColor: sheet ? const Color(0x99000000) : null,
            child: SubscriptionPage(sheet: sheet),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  if (!sheet) return child;
                  return SlideTransition(
                    position: animation.drive(
                      Tween(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).chain(CurveTween(curve: Curves.easeOutCubic)),
                    ),
                    child: child,
                  );
                },
          );
        },
      ),
      GoRoute(
        path: '/subscription/success',
        builder: (context, state) => const SubscriptionSuccessPage(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

Page<void> _mainTabPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}
