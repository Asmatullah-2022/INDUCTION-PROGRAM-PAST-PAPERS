import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/widgets/state_widgets.dart';
import '../home/home_providers.dart';
import '../phases/phase_screen.dart' show subjectsProvider;
import 'admin_guard.dart';
import 'admin_providers.dart';

/// Admin paper list — unlike the normal SubjectScreen, this shows every
/// paper regardless of content_status, across all 24 phase/subject slots,
/// so admins can see at a glance which slots are MISSING SOURCE PAPER.
class AdminPapersScreen extends ConsumerWidget {
  const AdminPapersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final papersAsync = ref.watch(adminAllPapersProvider);
    final phasesAsync = ref.watch(phasesProvider);
    final subjectsAsync = ref.watch(subjectsProvider);

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Manage Papers')),
        body: papersAsync.when(
          data: (papers) {
            final phaseNames = phasesAsync.maybeWhen(
              data: (phases) => {for (final p in phases) p.id: p.name},
              orElse: () => <String, String>{},
            );
            final subjectNames = subjectsAsync.maybeWhen(
              data: (subjects) => {for (final s in subjects) s.id: s.name},
              orElse: () => <String, String>{},
            );

            if (papers.isEmpty) {
              return const EmptyState(
                icon: Icons.description_outlined,
                title: 'No papers created yet',
                subtitle: 'Tap + to create the first paper slot for a phase/subject.',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: papers.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) return const AdminMissingSlotsBanner();
                final paper = papers[index - 1];
                return Card(
                  child: ListTile(
                    title: Text(
                      '${phaseNames[paper.phaseId] ?? '?'} • '
                      '${subjectNames[paper.subjectId] ?? '?'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(paper.title),
                    trailing: _StatusChip(status: paper.contentStatus),
                    onTap: () => context.push('/admin/papers/${paper.id}'),
                  ),
                );
              },
            );
          },
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(adminAllPapersProvider),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/admin/papers/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'PUBLISHED' => Colors.green,
      'VERIFIED' => Colors.teal,
      'UNDER_REVIEW' => Colors.orange,
      'ARCHIVED' => Colors.grey,
      _ => Colors.blueGrey,
    };
    return Chip(
      label: Text(status, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Shows the 24 expected phase/subject slots and highlights which ones
/// still have no paper at all (MISSING SOURCE PAPER), so admins can spot
/// gaps without cross-referencing the flat paper list mentally.
class AdminMissingSlotsBanner extends ConsumerWidget {
  const AdminMissingSlotsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final papersAsync = ref.watch(adminAllPapersProvider);
    return papersAsync.maybeWhen(
      data: (papers) {
        final filled = papers.map((p) => '${p.phaseId}::${p.subjectId}').toSet();
        final missing = AppConstants.totalExpectedPapers - filled.length;
        if (missing <= 0) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$missing of ${AppConstants.totalExpectedPapers} phase/subject slots have '
            'no paper yet — MISSING SOURCE PAPER.',
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
