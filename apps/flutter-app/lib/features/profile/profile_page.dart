import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../auth/ui/auth_sheet.dart';
import 'account_page.dart';

const profileVersionText = 'Version 1.0.0';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: authState.isLoading
            ? const Center(child: CircularProgressIndicator())
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
    final title = isUser ? 'Signed in' : 'Guest session';
    final emailText = session?.email ?? 'Unknown email';
    final userIdText = session?.userId ?? 'Unknown user';
    final identity = isUser
        ? emailText
        : (session?.anonymousId ?? 'Anonymous guest');

    return ListView(
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(identity, style: Theme.of(context).textTheme.bodyLarge),
        if (isUser) ...[
          const SizedBox(height: 4),
          Text(
            'ID: $userIdText',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (authState.pendingMigrationAnonymousId != null) ...[
          const SizedBox(height: 16),
          Text('Pending guest: ${authState.pendingMigrationAnonymousId}'),
        ],
        const SizedBox(height: 24),
        if (isUser) ...[
          Card(
            child: ListTile(
              title: const Text('Account'),
              subtitle: Text(identity),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/account'),
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          FilledButton(
            onPressed: () => showAuthSheet(context),
            child: const Text('Sign in / Sign up'),
          ),
          const SizedBox(height: 12),
        ],
        const _ProfileEntry(label: 'Customer Support'),
        const _ProfileEntry(label: 'Score'),
        const _ProfileEntry(label: 'Share With Friends'),
        const _ProfileEntry(label: 'Terms Of Use'),
        const _ProfileEntry(label: 'Privacy Policy'),
        if (isUser) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go('/');
              }
            },
            child: const Text('Log Out'),
          ),
        ] else ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              _confirmAndDelete(context, ref);
            },
            child: const Text('Delete account'),
          ),
        ],
        const SizedBox(height: 24),
        Text(profileVersionText, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDeleteAccountConfirmation(context);
    if (!context.mounted || !confirmed) {
      return;
    }

    await ref.read(authControllerProvider.notifier).deleteAccount();
  }
}

class _ProfileEntry extends StatelessWidget {
  const _ProfileEntry({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(label));
  }
}
