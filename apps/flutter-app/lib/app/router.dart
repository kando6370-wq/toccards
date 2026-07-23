import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/card_detail/card_detail_page.dart';
import '../features/collection/collection_page.dart';
import '../features/home/home_page.dart';
import '../features/onboarding/onboarding_gate.dart';
import '../features/profile/account_page.dart';
import '../features/profile/api_request_log_page.dart';
import '../features/profile/customer_support_page.dart';
import '../features/profile/profile_page.dart';
import '../features/scan/scan_page.dart';
import '../features/search/search_page.dart';
import '../features/search/set_detail_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          return const OnboardingGate(home: HomePage());
        },
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => _mainTabPage(state, const HomePage()),
      ),
      GoRoute(
        path: '/collection',
        pageBuilder: (context, state) =>
            _mainTabPage(state, const CollectionPage()),
      ),
      GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
      GoRoute(
        path: '/cards/:cardId',
        builder: (context, state) {
          return CardDetailPage(cardId: state.pathParameters['cardId'] ?? '');
        },
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) =>
            _mainTabPage(state, const SearchPage()),
      ),
      GoRoute(
        path: '/sets/:setCode',
        builder: (context, state) => SetDetailPage(
          setCode: state.pathParameters['setCode'] ?? '',
          game: state.uri.queryParameters['game'] ?? '',
          setName: state.uri.queryParameters['name'] ?? '',
        ),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) =>
            _mainTabPage(state, const ProfilePage()),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountPage(),
      ),
      GoRoute(
        path: '/customer-support',
        builder: (context, state) => const CustomerSupportPage(),
      ),
      GoRoute(
        path: '/profile/api-requests',
        builder: (context, state) => const ApiRequestLogPage(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

Page<void> _mainTabPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}
