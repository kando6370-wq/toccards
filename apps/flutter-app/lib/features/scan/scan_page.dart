import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum _ScanStatus { idle, scanning, matched, noMatch, review, added }

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  _ScanStatus _status = _ScanStatus.idle;
  Timer? _scanTimer;

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  void _startPhotoScan() {
    _completeScanWith(_ScanStatus.matched);
  }

  void _startLibraryScan() {
    _completeScanWith(_ScanStatus.noMatch);
  }

  void _completeScanWith(_ScanStatus result) {
    _scanTimer?.cancel();
    setState(() => _status = _ScanStatus.scanning);
    _scanTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _status = result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.qr_code_scanner_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            _ScanActions(
              status: _status,
              onPhotoPressed: _startPhotoScan,
              onLibraryPressed: _startLibraryScan,
              onReviewPressed: _status == _ScanStatus.matched
                  ? () => setState(() => _status = _ScanStatus.review)
                  : null,
            ),
            const SizedBox(height: 20),
            _ScanResult(
              status: _status,
              onSearchPressed: () => context.go('/search'),
              onAddPressed: () => setState(() => _status = _ScanStatus.added),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 2,
        onDestinationSelected: (index) {
          if (index == 0) {
            context.go('/');
            return;
          }
          if (index == 1) {
            context.go('/collection');
            return;
          }
          if (index == 3) {
            context.go('/search');
            return;
          }
          if (index == 4) {
            context.go('/profile');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            label: 'Collection',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ScanActions extends StatelessWidget {
  const _ScanActions({
    required this.status,
    required this.onPhotoPressed,
    required this.onLibraryPressed,
    required this.onReviewPressed,
  });

  final _ScanStatus status;
  final VoidCallback onPhotoPressed;
  final VoidCallback onLibraryPressed;
  final VoidCallback? onReviewPressed;

  @override
  Widget build(BuildContext context) {
    final isScanning = status == _ScanStatus.scanning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: isScanning ? null : onPhotoPressed,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Take Photo'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: isScanning ? null : onLibraryPressed,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from Library'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: onReviewPressed,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Review Your Matches'),
        ),
      ],
    );
  }
}

class _ScanResult extends StatelessWidget {
  const _ScanResult({
    required this.status,
    required this.onSearchPressed,
    required this.onAddPressed,
  });

  final _ScanStatus status;
  final VoidCallback onSearchPressed;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      _ScanStatus.idle => const SizedBox.shrink(),
      _ScanStatus.scanning => const _CenteredStatus(
        icon: Icons.document_scanner_outlined,
        title: 'Scanning',
      ),
      _ScanStatus.matched => const _MatchedCard(),
      _ScanStatus.noMatch => _NoMatch(onSearchPressed: onSearchPressed),
      _ScanStatus.review => _ReviewMatch(onAddPressed: onAddPressed),
      _ScanStatus.added => const _AddedCard(),
    };
  }
}

class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 40),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _MatchedCard extends StatelessWidget {
  const _MatchedCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.check_circle_outline),
        title: Text('Matched'),
        subtitle: Text('Mega Lucario ex'),
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.onSearchPressed});

  final VoidCallback onSearchPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CenteredStatus(
          icon: Icons.search_off_outlined,
          title: 'No Match Found',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onSearchPressed,
          icon: const Icon(Icons.search_outlined),
          label: const Text('Search Manually'),
        ),
      ],
    );
  }
}

class _ReviewMatch extends StatelessWidget {
  const _ReviewMatch({required this.onAddPressed});

  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collection Item',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Mega Lucario ex'),
            const Text('Adding to Main'),
            const Text('Raw'),
            const Text('Near Mint (NM)'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add this card'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddedCard extends StatelessWidget {
  const _AddedCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.check_circle_outline),
        title: Text('Added to Portfolio'),
        subtitle: Text('Mega Lucario ex'),
      ),
    );
  }
}
