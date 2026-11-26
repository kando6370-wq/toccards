import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/ui/kando_style.dart';
import '../../shared/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../auth/ui/auth_sheet.dart';
import 'google_play_controller.dart';
import 'subscription_controller.dart';

Future<bool> managePlaySubscription(PlayPolicy? policy) => launchUrl(
  Uri.https('play.google.com', '/store/account/subscriptions', {
    if (policy?.package != null && policy?.product != null) ...{
      'package': policy!.package!,
      'sku': policy.product!,
    },
  }),
  mode: LaunchMode.externalApplication,
);

class GooglePlayPage extends ConsumerStatefulWidget {
  const GooglePlayPage({required this.sheet, super.key});
  final bool sheet;
  @override
  ConsumerState<GooglePlayPage> createState() => _GooglePlayPageState();
}

class _GooglePlayPageState extends ConsumerState<GooglePlayPage> {
  late Future<({String title, List<PlayChoice> choices})> _catalog;
  StreamSubscription<String>? _events;
  String? _selected;
  bool _busy = false;
  String get _placement => widget.sheet ? 'modal' : 'page';
  @override
  void initState() {
    super.initState();
    _load();
    _events = ref.read(playPolicyProvider.notifier).events.listen((message) {
      if (!mounted) return;
      if (message == 'Premium is active') {
        Navigator.pop(context, SubscriptionPaywallResult.premiumUnlocked);
        return;
      }
      setState(() => _busy = false);
      _tell(message);
    });
  }

  void _load() {
    _catalog = ref.read(playPolicyProvider.notifier).choices(_placement);
  }

  void _tell(String message) {
    if (mounted) {
      showKandoTopToast(
        context,
        message: message,
        type: KandoTopToastType.info,
      );
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (_) {
      _tell('Google Play is unavailable. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(playPolicyProvider).current;
    ref.listen(authControllerProvider.select((a) => a.session?.dataSpaceId), (
      old,
      next,
    ) {
      if (old != next && mounted) {
        setState(() {
          _selected = null;
          _load();
        });
      }
    });
    return Scaffold(
      backgroundColor: KandoColors.ink,
      appBar: AppBar(
        title: const Text('Premium'),
        leading: CloseButton(onPressed: () => Navigator.maybePop(context)),
      ),
      body: SafeArea(
        child: FutureBuilder(
          future: _catalog,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final choices = snapshot.data?.choices ?? <PlayChoice>[];
            final selected =
                choices.where((c) => c.key == _selected).firstOrNull ??
                choices.where((c) => c.isDefault).firstOrNull ??
                choices.firstOrNull;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  snapshot.data?.title ?? 'Premium',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Unlimited scans, more folders, Performance and extended price history.',
                ),
                const SizedBox(height: 20),
                for (final choice in choices)
                  Card(
                    color: selected == choice
                        ? KandoColors.accentGlow10
                        : KandoColors.surface,
                    child: ListTile(
                      selected: selected == choice,
                      title: Text(choice.label),
                      subtitle: Text(choice.terms),
                      onTap: () => setState(() => _selected = choice.key),
                    ),
                  ),
                if (choices.isEmpty) ...[
                  Text(
                    snapshot.hasError
                        ? 'Prices could not be loaded.'
                        : 'No plans are available for this Play account.',
                  ),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Retry'),
                  ),
                ],
                if (selected != null && policy?.sales == true)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _action(() async {
                            if (ref
                                    .read(authControllerProvider)
                                    .session
                                    ?.isUser !=
                                true) {
                              await showAuthSheet(context);
                              if (mounted) setState(_load);
                              return;
                            }
                            if (!await ref
                                    .read(playPolicyProvider.notifier)
                                    .buy(_placement, selected) &&
                                mounted) {
                              setState(_load);
                              _tell(
                                'Plans changed. Review the current price and try again.',
                              );
                            }
                          }),
                    child: Text(
                      ref.watch(authControllerProvider).session?.isUser == true
                          ? 'Continue with Google Play'
                          : 'Sign in to subscribe',
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Your subscription renews automatically. You can cancel in Google Play.',
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _action(() async {
                          final message = await ref
                              .read(playPolicyProvider.notifier)
                              .restore();
                          if (!context.mounted) return;
                          if (ref.read(playPolicyProvider).current?.premium ==
                              true) {
                            Navigator.pop(
                              context,
                              SubscriptionPaywallResult.premiumRestored,
                            );
                          } else {
                            _tell(message);
                          }
                        }),
                  child: const Text('Restore purchases'),
                ),
                TextButton(
                  onPressed: () => _action(() async {
                    if (!await managePlaySubscription(policy)) {
                      _tell('Open Subscriptions in Google Play.');
                    }
                  }),
                  child: const Text('Manage in Google Play'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
