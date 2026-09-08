import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/ui/kando_modal.dart';
import '../../shared/ui/kando_style.dart';
import '../../shared/ui/load_state.dart';
import 'app_upgrade_models.dart';
import 'app_upgrade_repository.dart';

class AppUpgradeGate extends ConsumerStatefulWidget {
  const AppUpgradeGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppUpgradeGate> createState() => _AppUpgradeGateState();
}

class _AppUpgradeGateState extends ConsumerState<AppUpgradeGate>
    with WidgetsBindingObserver {
  final Set<String> _dismissedRecommendations = {};
  AppUpgradeDecision? _requiredUpdate;
  bool _openingStore = false;
  bool _storeFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() => ref.invalidate(appUpgradeDecisionProvider);

  @override
  Widget build(BuildContext context) {
    final check = ref.watch(appUpgradeDecisionProvider);
    final verified = !check.isLoading && !check.hasError ? check.value : null;
    if (verified != null) {
      _requiredUpdate = verified.forceUpdate ? verified : null;
    }
    final decision = verified ?? _requiredUpdate;
    final showUpdate =
        decision != null &&
        decision.showUpdate &&
        (decision.forceUpdate ||
            !_dismissedRecommendations.contains(decision.latestVersion));
    final blocked = verified == null || showUpdate;

    // The gate is above MaterialApp.router's Navigator. Rendering here also
    // keeps subsequent routes, deep links and store returns below enforcement.
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: blocked,
          child: ExcludeSemantics(
            excluding: blocked,
            child: IgnorePointer(ignoring: blocked, child: widget.child),
          ),
        ),
        if (blocked) ...[
          ModalBarrier(
            color: Colors.black54,
            dismissible: showUpdate && !decision.forceUpdate,
            onDismiss: showUpdate && !decision.forceUpdate
                ? () => _dismiss(decision)
                : null,
          ),
          if (showUpdate)
            SafeArea(
              child: KandoUpdateModal(
                title: 'Update Now',
                message: _storeFailed
                    ? 'Unable to open the store. Please try again.'
                    : 'New update available! Tap to upgrade',
                primaryLabel: _openingStore ? 'OPENING...' : 'INSTALL',
                secondaryLabel: 'LATER',
                forceUpdate: decision.forceUpdate,
                onPrimary: () => _openStore(decision),
                onSecondary: () => _dismiss(decision),
              ),
            )
          else
            ColoredBox(
              color: KandoColors.ink,
              child: SafeArea(
                child: check.isLoading
                    ? const KandoLoadingBlock()
                    : KandoFailureBlock(onRefresh: _refresh),
              ),
            ),
        ],
      ],
    );
  }

  void _dismiss(AppUpgradeDecision decision) {
    if (decision.forceUpdate) return;
    setState(() => _dismissedRecommendations.add(decision.latestVersion));
  }

  Future<void> _openStore(AppUpgradeDecision decision) async {
    if (_openingStore) return;
    setState(() {
      _openingStore = true;
      _storeFailed = false;
    });
    try {
      await ref.read(appStoreLauncherProvider).open(decision.storeUrl);
    } on Object {
      if (mounted) setState(() => _storeFailed = true);
    } finally {
      if (mounted) setState(() => _openingStore = false);
    }
  }
}
