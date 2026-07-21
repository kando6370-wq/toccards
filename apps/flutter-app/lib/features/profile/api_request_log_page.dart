import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/api/api_request_log.dart';
import '../../shared/ui/kando_style.dart';
import 'profile_detail_scaffold.dart';

class ApiRequestLogPage extends ConsumerWidget {
  const ApiRequestLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cutoff = DateTime.now().subtract(apiRequestLogRetention);
    final entries = [
      for (final entry in ref.watch(apiRequestLogProvider))
        if (!entry.startedAt.isBefore(cutoff)) entry,
    ].reversed.toList();
    final errorEntries = [
      for (final entry in entries)
        if (entry.hasError) entry,
    ];

    return DefaultTabController(
      length: 2,
      child: ProfileDetailScaffold(
        semanticsLabel: 'API request log',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'API Requests',
                      style: TextStyle(
                        color: KandoColors.text,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 34 / 28,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('api-request-log-refresh'),
                    tooltip: 'Refresh',
                    onPressed: () {
                      ref.read(apiRequestLogProvider.notifier).prune();
                    },
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(40),
                      foregroundColor: KandoColors.text,
                      backgroundColor: KandoColors.elevatedSurface,
                    ),
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Last hour - ${entries.length} request${entries.length == 1 ? '' : 's'}, ${errorEntries.length} error${errorEntries.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: KandoColors.mutedText.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: KandoColors.elevatedSurface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: KandoColors.border.withValues(alpha: 0.35),
                  ),
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: KandoColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  dividerColor: Colors.transparent,
                  labelColor: KandoColors.accent,
                  unselectedLabelColor: KandoColors.mutedText,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                  tabs: const [
                    Tab(text: 'Requests'),
                    Tab(text: 'Errors'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: TabBarView(
                  children: [
                    _LogList(
                      key: const Key('api-request-log-list'),
                      entries: entries,
                      emptyMessage: 'No requests in the last hour',
                    ),
                    _LogList(
                      key: const Key('api-request-error-log-list'),
                      entries: errorEntries,
                      emptyMessage: 'No error requests in the last hour',
                      showErrorDetails: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogList extends StatelessWidget {
  const _LogList({
    super.key,
    required this.entries,
    required this.emptyMessage,
    this.showErrorDetails = false,
  });

  final List<ApiRequestLogEntry> entries;
  final String emptyMessage;
  final bool showErrorDetails;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: TextStyle(
            color: KandoColors.mutedText.withValues(alpha: 0.7),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _ApiRequestLogTile(
          entry: entries[index],
          showErrorDetails: showErrorDetails,
        );
      },
    );
  }
}

class _ApiRequestLogTile extends StatelessWidget {
  const _ApiRequestLogTile({
    required this.entry,
    this.showErrorDetails = false,
  });

  final ApiRequestLogEntry entry;
  final bool showErrorDetails;

  @override
  Widget build(BuildContext context) {
    final statusColor = entry.succeeded ? KandoColors.gain : KandoColors.error;
    final statusText = entry.statusCode == null
        ? (entry.succeeded ? 'OK' : 'ERR')
        : entry.statusCode.toString();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: KandoColors.elevatedSurface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KandoColors.border.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MethodPill(entry.method),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${entry.durationMs} ms',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: KandoColors.money,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              entry.url.toString(),
              style: const TextStyle(
                color: KandoColors.text,
                fontSize: 13,
                height: 18 / 13,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  _formatClock(entry.startedAt),
                  style: TextStyle(
                    color: KandoColors.mutedText.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (showErrorDetails && entry.errorSummary != null) ...[
              const SizedBox(height: 12),
              _ErrorBlock(title: 'Summary', text: entry.errorSummary!),
            ],
            if (showErrorDetails && entry.errorDetails != null) ...[
              const SizedBox(height: 10),
              _ErrorBlock(title: 'Details', text: entry.errorDetails!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KandoColors.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KandoColors.error.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: KandoColors.error,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              text,
              style: TextStyle(
                color: KandoColors.text.withValues(alpha: 0.9),
                fontSize: 12,
                height: 17 / 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodPill extends StatelessWidget {
  const _MethodPill(this.method);

  final String method;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 54),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: KandoColors.ink,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KandoColors.accent.withValues(alpha: 0.18)),
      ),
      child: Text(
        method,
        style: const TextStyle(
          color: KandoColors.accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _formatClock(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}
