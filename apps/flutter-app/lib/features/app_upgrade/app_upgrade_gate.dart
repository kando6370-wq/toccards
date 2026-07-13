import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_upgrade_models.dart';
import 'app_upgrade_repository.dart';

class AppUpgradeGate extends ConsumerStatefulWidget {
  const AppUpgradeGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppUpgradeGate> createState() => _AppUpgradeGateState();
}

class _AppUpgradeGateState extends ConsumerState<AppUpgradeGate> {
  final Set<String> _shownDecisions = {};

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppUpgradeDecision>>(appUpgradeDecisionProvider, (
      _,
      next,
    ) {
      next.whenData(_showWhenNeeded);
    });

    return widget.child;
  }

  void _showWhenNeeded(AppUpgradeDecision decision) {
    if (!decision.showUpdate) return;

    final key = '${decision.latestVersion}:${decision.forceUpdate}';
    if (_shownDecisions.contains(key)) return;
    _shownDecisions.add(key);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showUpgradeDialog(decision);
    });
  }

  Future<void> _showUpgradeDialog(AppUpgradeDecision decision) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !decision.forceUpdate,
      builder: (dialogContext) {
        final dialog = AlertDialog(
          title: Text(decision.title),
          content: Text(decision.message),
          actions: [
            if (!decision.forceUpdate)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Later'),
              ),
            FilledButton(
              onPressed: () {
                ref.read(appStoreLauncherProvider).open(decision.storeUrl);
              },
              child: const Text('Update Now'),
            ),
          ],
        );

        return decision.forceUpdate
            ? PopScope(canPop: false, child: dialog)
            : dialog;
      },
    );
  }
}
