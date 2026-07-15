import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import '../auth/ui/auth_sheet.dart';
import '../app_upgrade/app_upgrade_repository.dart';
import '../../shared/ui/toast.dart';
import 'account_page.dart';
import 'profile_actions.dart';

final profileVersionProvider = FutureProvider<String>((ref) {
  return ref.watch(installedVersionReaderProvider).currentVersion();
});

// Destructive action red from the Figma spec (no matching design token exists).
const _dangerColor = Color(0xFFFF8989);

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return KandoTabScaffold(
      currentTab: KandoMainTab.profile,
      body: SafeArea(
        child: authState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : authState.hasError
            ? KandoFailureBlock(
                onRefresh: () {
                  ref.read(authControllerProvider.notifier).retryStartup();
                },
              )
            : _ProfileContent(authState: authState),
      ),
    );
  }
}

class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = authState.session;
    final isUser = session?.ownerType == OwnerType.user;
    final emailText = session?.email ?? 'Unknown email';
    final userIdText = session?.userId ?? 'Unknown user';
    final versionText = ref
        .watch(profileVersionProvider)
        .when(
          data: (version) => 'Version $version',
          error: (_, _) => 'Version unavailable',
          loading: () => 'Version',
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
      children: [
        _SectionLabel('Account'),
        if (isUser)
          _MenuCard(
            children: [
              _AccountRow(
                email: emailText,
                userId: userIdText,
                onTap: () => context.push('/account'),
              ),
            ],
          )
        else
          _MenuCard(
            children: [
              _MenuRow(
                icon: Icons.person_outline,
                label: 'Sign in / Sign up',
                onTap: () => showAuthSheet(context),
              ),
            ],
          ),
        const SizedBox(height: 24),
        _SectionLabel('Support'),
        _MenuCard(
          children: [
            _MenuRow(
              icon: Icons.mail_outline,
              label: 'Customer Support',
              onTap: () => context.push('/customer-support'),
            ),
            _MenuRow(
              icon: Icons.star_outline,
              label: 'Score',
              onTap: () => _runProfileAction(
                context,
                () => ref.read(profileActionsProvider).requestScore(),
              ),
            ),
            _MenuRow(
              icon: Icons.share_outlined,
              label: 'Share With Friends',
              onTap: () => _runProfileAction(
                context,
                () => ref.read(profileActionsProvider).shareWithFriends(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionLabel('Others'),
        _MenuCard(
          children: [
            _MenuRow(
              icon: Icons.description_outlined,
              label: 'Terms Of Use',
              onTap: () => _runProfileAction(
                context,
                () => ref.read(profileActionsProvider).openTerms(),
              ),
            ),
            _MenuRow(
              icon: Icons.shield_outlined,
              label: 'Privacy Policy',
              onTap: () => _runProfileAction(
                context,
                () => ref.read(profileActionsProvider).openPrivacy(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        if (isUser)
          Center(
            child: TextButton.icon(
              onPressed: () async {
                await _logout(context, ref);
              },
              style: TextButton.styleFrom(
                foregroundColor: KandoColors.text,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Log Out', style: TextStyle(fontSize: 16)),
            ),
          )
        else
          Center(
            child: TextButton.icon(
              onPressed: () => _confirmAndDelete(context, ref),
              style: TextButton.styleFrom(
                foregroundColor: _dangerColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.delete_outline, size: 20),
              label: const Text(
                'Delete Account',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            versionText,
            style: TextStyle(
              color: KandoColors.mutedText.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _runProfileAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Exception {
      if (context.mounted) {
        showKandoToast(context, message: profileActionFailureText);
      }
    }
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDeleteAccountConfirmation(context);
    if (!context.mounted || !confirmed) {
      return;
    }

    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
    } on Exception {
      if (context.mounted) {
        showKandoToast(context, message: authAccountActionFailedMessage);
      }
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authControllerProvider.notifier).logout();
      if (context.mounted) {
        context.go('/profile');
      }
    } on AuthNetworkException {
      if (context.mounted) {
        showKandoNetworkToast(context);
      }
    } on Exception {
      if (context.mounted) {
        showKandoFailureToast(context);
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: KandoColors.mutedText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            color: KandoColors.border.withValues(alpha: 0.3),
          ),
        );
      }
      rows.add(children[i]);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KandoColors.elevatedSurface.withValues(alpha: 0.6),
            KandoColors.ink.withValues(alpha: 0.95),
          ],
        ),
        border: Border.all(color: KandoColors.accent.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(children: rows),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _IconBadge(icon: icon),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: KandoColors.text,
                  fontSize: 16,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: KandoColors.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KandoColors.elevatedSurface,
        border: Border.all(color: KandoColors.border.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: 18, color: KandoColors.text),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.email,
    required this.userId,
    this.onTap,
  });

  final String email;
  final String userId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = email.trim().isNotEmpty
        ? email.trim().characters.first.toUpperCase()
        : '?';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KandoColors.ink,
                border: Border.all(
                  color: KandoColors.accent.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: KandoColors.accent.withValues(alpha: 0.15),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  color: KandoColors.accent,
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KandoColors.text,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: $userId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: KandoColors.mutedText.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: KandoColors.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}
