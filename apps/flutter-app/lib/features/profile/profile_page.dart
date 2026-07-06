import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

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
    final identity = isUser
        ? (session?.email ?? session?.userId ?? 'User')
        : (session?.anonymousId ?? 'Anonymous guest');

    return ListView(
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(identity, style: Theme.of(context).textTheme.bodyLarge),
        if (authState.pendingMigrationAnonymousId != null) ...[
          const SizedBox(height: 16),
          Text('Pending guest: ${authState.pendingMigrationAnonymousId}'),
        ],
        const SizedBox(height: 24),
        if (isUser) ...[
          FilledButton(
            onPressed: () {
              ref.read(authControllerProvider.notifier).logout();
            },
            child: const Text('Log out'),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton(
          onPressed: () {
            ref.read(authControllerProvider.notifier).deleteAccount();
          },
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
