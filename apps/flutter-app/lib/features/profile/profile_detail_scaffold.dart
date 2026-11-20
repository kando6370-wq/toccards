import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/ui/kando_style.dart';

class ProfileDetailScaffold extends StatelessWidget {
  const ProfileDetailScaffold({
    required this.child,
    this.wideChild,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final Widget? wideChild;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KandoColors.ink,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
            final wide =
                wideChild != null &&
                constraints.maxWidth >= 840 &&
                constraints.maxHeight >= 480 &&
                !keyboardVisible;
            final content = Column(
              children: [
                const _ProfileDetailBackButton(),
                const SizedBox(height: 32),
                Expanded(child: wide ? wideChild! : child),
              ],
            );

            final canvas = SizedBox(
              key: const Key('profile-detail-canvas'),
              width: double.infinity,
              child: semanticsLabel == null
                  ? content
                  : Semantics(
                      container: true,
                      explicitChildNodes: true,
                      label: semanticsLabel,
                      child: content,
                    ),
            );

            return Center(
              child: wide
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: canvas,
                    )
                  : canvas,
            );
          },
        ),
      ),
    );
  }
}

class _ProfileDetailBackButton extends StatelessWidget {
  const _ProfileDetailBackButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
    );
  }
}
