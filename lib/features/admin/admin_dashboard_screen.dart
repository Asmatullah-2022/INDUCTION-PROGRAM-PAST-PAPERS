import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/models/admin_dashboard_stats.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';

final adminDashboardStatsProvider = FutureProvider<AdminDashboardStats>((ref) {
  return ref.read(adminRepositoryProvider).getDashboardStats();
});

/// Content QA dashboard (spec section 60 + the admin content-management
/// stage): every number here comes from a real query — an empty database
/// shows zeros, never a placeholder.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminDashboardStatsProvider);

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Admin — Content Dashboard')),
        body: statsAsync.when(
          data: (stats) => RefreshIndicator(
            onRefresh: () => ref.refresh(adminDashboardStatsProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusGrid(stats: stats),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Published Papers by Phase',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          '${stats.publishedPapers} / ${AppConstants.totalExpectedPapers} expected',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        ...stats.publishedByPhaseName.entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text('${e.key}: ${e.value}/8'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Content Totals', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Total Subjects: ${stats.totalSubjects}'),
                        Text('Total Questions: ${stats.totalQuestions}'),
                        Text('  MCQs: ${stats.mcqCount}'),
                        Text('  Short: ${stats.shortCount}'),
                        Text('  Long: ${stats.longCount}'),
                        Text('Total Users: ${stats.totalUsers}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Question Quality Status',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Verified: ${stats.verifiedQuestionCount}'),
                        Text('Questionable: ${stats.questionableCount}'),
                        Text('OCR Uncertain: ${stats.ocrUncertainCount}'),
                        Text('Paper Error: ${stats.paperErrorCount}'),
                        Text('Answer Uncertain: ${stats.answerUncertainCount}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Manage Papers'),
                        subtitle: const Text(
                            'Create papers, upload originals, edit sections/questions'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/admin/papers'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.grid_view_outlined),
                        title: const Text('Content Coverage'),
                        subtitle: const Text('All 24 phase/subject slots and their status'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/admin/coverage'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.file_upload_outlined),
                        title: const Text('Import Content'),
                        subtitle: const Text('Bulk-import a paper from a validated JSON file'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/admin/import'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.rule_folder_outlined),
                        title: const Text('Review Questionable Questions'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/admin/review'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.history_outlined),
                        title: const Text('Audit Log'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/admin/audit-log'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(adminDashboardStatsProvider),
          ),
        ),
      ),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  final AdminDashboardStats stats;
  const _StatusGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (_StatusTileData('Total Papers', stats.totalPapers, Colors.blueGrey)),
      (_StatusTileData('Draft', stats.draftPapers, Colors.grey)),
      (_StatusTileData('Needs Review', stats.needsReviewPapers, Colors.orange)),
      (_StatusTileData('Verified', stats.verifiedPapers, Colors.teal)),
      (_StatusTileData('Published', stats.publishedPapers, Colors.green)),
      (_StatusTileData('Missing Source', stats.missingSourcePapers, Colors.red)),
      (_StatusTileData('Archived', stats.archivedPapers, Colors.blueGrey)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisExtent: 84,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, index) => _StatusTile(data: tiles[index]),
    );
  }
}

class _StatusTileData {
  final String label;
  final int value;
  final Color color;
  const _StatusTileData(this.label, this.value, this.color);
}

class _StatusTile extends StatelessWidget {
  final _StatusTileData data;
  const _StatusTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${data.value}',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, color: data.color)),
            const SizedBox(height: 4),
            Text(data.label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
