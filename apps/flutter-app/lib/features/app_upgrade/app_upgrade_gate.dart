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
  bool _homeEntered = false;
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
    if (_homeEntered && state == AppLifecycleState.resumed) _refresh();
  }

  void _enterHome() {
    if (!mounted || _homeEntered) return;
    setState(() => _homeEntered = true);
  }

  void _refresh() => ref.invalidate(appUpgradeDecisionProvider);

  @override
  Widget build(BuildContext context) {
    final check = _homeEntered
        ? ref.watch(appUpgradeDecisionProvider)
        : const AsyncValue<AppUpgradeDecision>.loading();
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
    final blocked = _homeEntered && (verified == null || showUpdate);

    // Start only after Home is displayed, then retain enforcement above the
    // Navigator so route changes and store returns cannot bypass a forced update.
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

/// Activates the app-wide upgrade gate when the actual Home content is shown.
/// Place inside startup gates, not around the route that also hosts onboarding.
class AppUpgradeHomeEntry extends StatefulWidget {
  const AppUpgradeHomeEntry({required this.child, super.key});

  final Widget child;

  @override
  State<AppUpgradeHomeEntry> createState() => _AppUpgradeHomeEntryState();
}

class _AppUpgradeHomeEntryState extends State<AppUpgradeHomeEntry> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (route != null && !route.isCurrent)) return;
      context.findAncestorStateOfType<_AppUpgradeGateState>()?._enterHome();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
