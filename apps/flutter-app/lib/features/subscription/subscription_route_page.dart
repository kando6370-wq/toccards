import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const subscriptionTransitionDuration = Duration(milliseconds: 350);
const subscriptionSheetAnimationStyle = AnimationStyle(
  duration: subscriptionTransitionDuration,
  reverseDuration: subscriptionTransitionDuration,
);

const _mainTabSubscriptionSources = {
  'home',
  'search',
  'scan',
  'collection',
  'profile',
};

bool subscriptionPageEntersFromBottom(String? source) {
  return _mainTabSubscriptionSources.contains(source);
}

class KandoSubscriptionPage<T> extends CustomTransitionPage<T> {
  KandoSubscriptionPage({
    required super.key,
    required String? source,
    Duration duration = subscriptionTransitionDuration,
    required super.child,
  }) : super(
         transitionDuration: subscriptionPageEntersFromBottom(source)
             ? duration
             : Duration.zero,
         reverseTransitionDuration: subscriptionPageEntersFromBottom(source)
             ? duration
             : Duration.zero,
         opaque: true,
         transitionsBuilder: (_, animation, _, child) {
           if (!subscriptionPageEntersFromBottom(source)) return child;
           return SlideTransition(
             key: const Key('subscription-page-bottom-transition'),
             position: animation.drive(
               Tween<Offset>(
                 begin: const Offset(0, 1),
                 end: Offset.zero,
               ).chain(CurveTween(curve: Curves.easeOutCubic)),
             ),
             child: child,
           );
         },
       );
}
