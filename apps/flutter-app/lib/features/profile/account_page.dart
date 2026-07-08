import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../../shared/ui/toast.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final session = authState.session;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: authState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : _AccountContent(session: session),
      ),
    );
  }
}

class _AccountContent extends ConsumerWidget {
  const _AccountContent({required this.session});

  final AuthSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (session?.isUser != true) {
      return const Center(child: Text('Guest session'));
    }

    return ListView(
      children: [
        const Text('Email'),
        Text(session!.email ?? 'Unknown email'),
        const SizedBox(height: 16),
        const Text('User ID'),
        Text(session!.userId ?? 'Unknown user'),
        const SizedBox(height: 16),
        const Text('Login method'),
        const Text('Email login'),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () async {
            await ref.read(authControllerProvider.notifier).logout();
            if (context.mounted) {
              context.go('/');
            }
          },
          child: const Text('Log Out'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () async {
            final confirmed = await showDeleteAccountConfirmation(context);
            if (!context.mounted || !confirmed) {
              return;
            }

            try {
              await ref.read(authControllerProvider.notifier).deleteAccount();
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
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

Future<bool> showDeleteAccountConfirmation(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text("This action is permanent and can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );

  return result ?? false;
}
