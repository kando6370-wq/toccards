import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/onboarding/onboarding_gate.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';

void main() {
  testWidgets(
    'startup branding stays visible while first-launch state is unresolved because Home must not flash',
    (tester) async {
      final repository = _PendingOnboardingRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: OnboardingGate(home: Text('Home ready')),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('onboarding-loading')), findsOneWidget);
      expect(find.text('Card AI'), findsOneWidget);
      expect(find.text('LOADING YOUR COLLECTION...'), findsOneWidget);
      expect(find.text('Home ready'), findsNothing);

      repository.readResult.complete(true);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('onboarding-loading')), findsNothing);
      expect(find.text('Home ready'), findsOneWidget);
    },
  );
}

class _PendingOnboardingRepository implements OnboardingRepository {
  final readResult = Completer<bool>();

  @override
  Future<bool> readCompleted() => readResult.future;

  @override
  Future<void> markCompleted() async {}
}
