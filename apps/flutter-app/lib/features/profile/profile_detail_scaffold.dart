import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/ui/kando_style.dart';

class ProfileDetailScaffold extends StatelessWidget {
  const ProfileDetailScaffold({
    required this.child,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        SizedBox(
          height: 38,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: IconButton(
                key: const Key('profile-back-button'),
                tooltip: 'Back',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/profile');
                  }
                },
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(38),
                  minimumSize: const Size.square(38),
                  maximumSize: const Size.square(38),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: KandoColors.text,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                ),
                icon: const Icon(Icons.chevron_left_rounded, size: 26),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Expanded(child: child),
      ],
    );

    return Scaffold(
      backgroundColor: KandoColors.ink,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            key: const Key('profile-detail-canvas'),
            constraints: const BoxConstraints(maxWidth: 390),
            child: semanticsLabel == null
                ? content
                : Semantics(
                    container: true,
                    explicitChildNodes: true,
                    label: semanticsLabel,
                    child: content,
                  ),
          ),
        ),
      ),
    );
  }
}
