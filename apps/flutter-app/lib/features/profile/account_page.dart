import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../../shared/ui/toast.dart';

// Destructive action red from the Figma spec (no matching design token exists).
const _dangerColor = Color(0xFFFF8989);

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final session = authState.session;

    return Scaffold(
      backgroundColor: KandoColors.ink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Account'),
      ),
      body: authState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _AccountContent(session: session),
    );
  }
}

class _AccountContent extends ConsumerWidget {
  const _AccountContent({required this.session});

  final AuthSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (session?.isUser != true) {
      return const Center(
        child: Text(
          'Guest session',
          style: TextStyle(color: KandoColors.mutedText, fontSize: 16),
        ),
      );
    }

    final email = session!.email ?? 'Unknown email';
    final userId = session!.userId ?? 'Unknown user';
    final initial = email.trim().isNotEmpty
        ? email.trim().characters.first.toUpperCase()
        : '?';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        const SizedBox(height: 12),
        _ProfileHeader(initial: initial, email: email, userId: userId),
        const SizedBox(height: 32),
        _SectionLabel('Account Details'),
        const SizedBox(height: 8),
        _DetailRow(
          icon: Icons.mail_outline,
          label: 'EMAIL',
          value: email,
        ),
        const SizedBox(height: 8),
        _DetailRow(
          icon: Icons.fingerprint,
          label: 'ID',
          value: userId,
        ),
        const SizedBox(height: 8),
        _DetailRow(
          icon: Icons.vpn_key_outlined,
          label: 'LOGIN METHOD',
          value: 'EMAIL',
          trailing: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KandoColors.accent,
              boxShadow: [
                BoxShadow(
                  color: KandoColors.accent.withValues(alpha: 0.8),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        _SectionLabel('Management'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ManagementButton(
                icon: Icons.logout,
                label: 'Log Out',
                background: KandoColors.elevatedSurface,
                borderColor: KandoColors.border.withValues(alpha: 0.4),
                foreground: KandoColors.text,
                onTap: () async {
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) {
                    context.go('/profile');
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ManagementButton(
                icon: Icons.delete_outline,
                label: 'Delete Account',
                background: _dangerColor.withValues(alpha: 0.15),
                borderColor: _dangerColor.withValues(alpha: 0.3),
                foreground: _dangerColor,
                onTap: () async {
                  final confirmed = await showDeleteAccountConfirmation(
                    context,
                  );
                  if (!context.mounted || !confirmed) {
                    return;
                  }

                  try {
                    await ref
                        .read(authControllerProvider.notifier)
                        .deleteAccount();
                    if (context.mounted) {
                      context.go('/profile');
                    }
                  } on Exception {
                    if (context.mounted) {
                      showKandoToast(
                        context,
                        message: authAccountActionFailedMessage,
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.initial,
    required this.email,
    required this.userId,
  });

  final String initial;
  final String email;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 96,
              height: 96,
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
                  fontSize: 36,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KandoColors.accent,
                  border: Border.all(color: KandoColors.ink, width: 4),
                ),
                child: const Icon(
                  Icons.verified,
                  size: 16,
                  color: KandoColors.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          email,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: KandoColors.text,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Opacity(
          opacity: 0.7,
          child: Text(
            'ID: $userId',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: KandoColors.mutedText,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: KandoColors.mutedText.withValues(alpha: 0.6),
          fontSize: 16,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KandoColors.elevatedSurface, KandoColors.ink],
        ),
        border: Border.all(color: KandoColors.accent.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: KandoColors.elevatedSurface,
            ),
            child: Icon(icon, size: 20, color: KandoColors.accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: KandoColors.mutedText,
                    fontSize: 16,
                  ),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KandoColors.text,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagementButton extends StatelessWidget {
  const _ManagementButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.borderColor,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color borderColor;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(color: foreground, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> showDeleteAccountConfirmation(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: KandoColors.elevatedSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: const TextStyle(
          color: KandoColors.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: KandoColors.mutedText,
          fontSize: 15,
          height: 1.4,
        ),
        title: const Text('Delete Account?'),
        content: const Text("This action is permanent and can't be undone."),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: KandoColors.mutedText,
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: _dangerColor,
              foregroundColor: KandoColors.ink,
            ),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );

  return result ?? false;
}
