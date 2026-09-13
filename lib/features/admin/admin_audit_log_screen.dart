import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/audit_log.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';

final adminAuditLogProvider = FutureProvider<List<AuditLog>>((ref) {
  return ref.read(adminRepositoryProvider).getRecentAuditLogs();
});

/// Read-only audit trail (spec item 13): every CREATE/UPDATE/DELETE the
/// admin repository performs, plus STATUS_TRANSITION and
/// AUTO_INVALIDATE_VERIFICATION rows written by the database itself (see
/// 006_admin_workflow.sql). Protected the same way as every other admin
/// screen — profiles.is_admin server-side RLS, not this client-side guard.
class AdminAuditLogScreen extends ConsumerWidget {
  const AdminAuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(adminAuditLogProvider);
    final formatter = DateFormat('MMM d, HH:mm');

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Audit Log')),
        body: logsAsync.when(
          data: (logs) {
            if (logs.isEmpty) {
              return const EmptyState(
                icon: Icons.history_outlined,
                title: 'No admin actions recorded yet',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final log = logs[index];
                return Card(
                  child: ListTile(
                    leading: Icon(_iconFor(log.action)),
                    title: Text('${log.action} — ${log.tableName}'),
                    subtitle: Text(formatter.format(log.createdAt)),
                  ),
                );
              },
            );
          },
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(adminAuditLogProvider),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String action) => switch (action) {
        'CREATE' => Icons.add_circle_outline,
        'UPDATE' => Icons.edit_outlined,
        'DELETE' => Icons.delete_outline,
        'STATUS_TRANSITION' => Icons.swap_horiz,
        'AUTO_INVALIDATE_VERIFICATION' => Icons.warning_amber_rounded,
        _ => Icons.circle_outlined,
      };
}
