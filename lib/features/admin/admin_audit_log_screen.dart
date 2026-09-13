import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pagination/paginated_result.dart';
import '../../core/pagination/pagination_notifier.dart';
import '../../core/pagination/pagination_state.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/models/audit_log.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';

/// Keyset-paginated audit trail — see docs/PERFORMANCE_AUDIT.md for why
/// this replaced a flat top-100 fetch with no way to see older entries.
class AdminAuditLogNotifier extends PaginationNotifier<AuditLog> {
  @override
  Future<PaginatedResult<AuditLog>> fetchPage(String? cursor, int limit) {
    return ref.read(adminRepositoryProvider).getAuditLogsPage(cursor: cursor, limit: limit);
  }
}

final adminAuditLogProvider = NotifierProvider<AdminAuditLogNotifier, PaginationState<AuditLog>>(
  AdminAuditLogNotifier.new,
);

/// Read-only audit trail (spec item 13): every CREATE/UPDATE/DELETE the
/// admin repository performs, plus STATUS_TRANSITION and
/// AUTO_INVALIDATE_VERIFICATION rows written by the database itself (see
/// 006_admin_workflow.sql). Protected the same way as every other admin
/// screen — profiles.is_admin server-side RLS, not this client-side guard.
class AdminAuditLogScreen extends ConsumerStatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  ConsumerState<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends ConsumerState<AdminAuditLogScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(adminAuditLogProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminAuditLogProvider);
    final formatter = DateFormat('MMM d, HH:mm');

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Audit Log')),
        body: _buildBody(state, formatter),
      ),
    );
  }

  Widget _buildBody(PaginationState<AuditLog> state, DateFormat formatter) {
    if (state.isLoading) return const LoadingList();
    if (state.error != null && state.items.isEmpty) {
      return ErrorState(
        message: state.error!,
        onRetry: () => ref.read(adminAuditLogProvider.notifier).refresh(),
      );
    }
    if (state.items.isEmpty) {
      return const EmptyState(
        icon: Icons.history_outlined,
        title: 'No admin actions recorded yet',
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(adminAuditLogProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final log = state.items[index];
          return Card(
            child: ListTile(
              leading: Icon(_iconFor(log.action)),
              title: Text('${log.action} — ${log.tableName}'),
              subtitle: Text(formatter.format(log.createdAt)),
            ),
          );
        },
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
