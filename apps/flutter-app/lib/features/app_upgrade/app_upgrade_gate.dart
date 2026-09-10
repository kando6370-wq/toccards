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
  bool _homeWasVisible = false;
  final Set<_AppUpgradeHomeEntryState> _homeEntries = {};
  final Set<String> _dismissedRecommendations = {};
  AppUpgradeDecision? _lastVerified;
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
    if (state == AppLifecycleState.resumed &&
        (_homeVisible || _lastVerified?.forceUpdate == true)) {
      _refresh();
    }
  }

  bool get _homeVisible => _homeEntries.any((entry) => entry.isCurrentHome);

  void _updateHome(_AppUpgradeHomeEntryState entry, {bool removed = false}) {
    if (!mounted) return;
    if (removed) {
      _homeEntries.remove(entry);
    } else {
      _homeEntries.add(entry);
    }
    final visible = _homeVisible;
    if (_homeWasVisible == visible) return;
    final recheck = visible && _homeEntered;
    setState(() {
      _homeWasVisible = visible;
      if (visible) _homeEntered = true;
    });
    if (recheck) _refresh();
  }

  void _refresh() {
    if (_homeEntered && !ref.read(appUpgradeDecisionProvider).isLoading) {
      ref.invalidate(appUpgradeDecisionProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final check = _homeEntered
        ? ref.watch(appUpgradeDecisionProvider)
        : const AsyncValue<AppUpgradeDecision>.loading();
    final verified = !check.isLoading && !check.hasError ? check.value : null;
    final homeVisible = _homeVisible;
    // A result arriving after Home was covered must not introduce a new prompt
    // on another page. An already enforced update can still be reverified there.
    if (verified != null &&
        (homeVisible || _lastVerified?.forceUpdate == true)) {
      _lastVerified = verified;
    }
    final decision = _lastVerified;
    final showUpdate =
        decision != null &&
        decision.showUpdate &&
        (decision.forceUpdate ||
            homeVisible &&
                !_dismissedRecommendations.contains(decision.latestVersion));
    final blocked = showUpdate || homeVisible && _lastVerified == null;

    // Only the initial Home check blocks on loading/failure. Later Home checks
    // retain verified content; a known mandatory update remains above all routes.
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

/// Reports whether the actual Home content is on the current route.
/// Place inside startup gates, not around the route that also hosts onboarding.
class AppUpgradeHomeEntry extends StatefulWidget {
  const AppUpgradeHomeEntry({required this.child, super.key});

  final Widget child;

  @override
  State<AppUpgradeHomeEntry> createState() => _AppUpgradeHomeEntryState();
}

class _AppUpgradeHomeEntryState extends State<AppUpgradeHomeEntry> {
  _AppUpgradeGateState? _gate;
  ModalRoute<dynamic>? _route;

  bool get isCurrentHome => mounted && (_route == null || _route!.isCurrent);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _gate = context.findAncestorStateOfType<_AppUpgradeGateState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _gate?._updateHome(this);
    });
  }

  @override
  void dispose() {
    final gate = _gate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gate?._updateHome(this, removed: true);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
