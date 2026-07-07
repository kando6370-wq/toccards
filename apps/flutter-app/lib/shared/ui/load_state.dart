import 'package:flutter/material.dart';

const noContentAvailableText = 'No content available';
const refreshText = 'Refresh';

enum KandoLoadStatus { loading, content, failure }

class KandoLoadingBlock extends StatelessWidget {
  const KandoLoadingBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class KandoFailureBlock extends StatelessWidget {
  const KandoFailureBlock({required this.onRefresh, super.key});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                noContentAvailableText,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRefresh,
                child: const Text(refreshText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KandoEmptyBlock extends StatelessWidget {
  const KandoEmptyBlock({
    required this.title,
    this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final String title;
  final String? body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (body != null) ...[const SizedBox(height: 8), Text(body!)],
            if (primaryLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
            ],
            if (secondaryLabel != null)
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ),
      ),
    );
  }
}
