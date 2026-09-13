import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/paper.dart';
import '../../shared/widgets/state_widgets.dart';
import '../home/home_providers.dart';
import '../phases/phase_screen.dart' show subjectsProvider;
import 'admin_guard.dart';
import 'admin_papers_screen.dart' show PaperStatusBadge;
import 'admin_providers.dart';

/// Content Coverage: every phase/subject slot (all 24), each showing its
/// real status — VERIFIED / NEEDS REVIEW / DRAFT / MISSING SOURCE /
/// PUBLISHED / ARCHIVED — never a fabricated "available" state for a slot
/// that has no paper at all. A slot with no row in `papers` yet is always
/// shown as Missing Source, identical to a Draft paper with no file.
class AdminContentCoverageScreen extends ConsumerWidget {
  const AdminContentCoverageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phasesAsync = ref.watch(phasesProvider);
    final subjectsAsync = ref.watch(subjectsProvider);
    final papersAsync = ref.watch(adminAllPapersProvider);

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Content Coverage')),
        body: phasesAsync.when(
          data: (phases) => subjectsAsync.when(
            data: (subjects) => papersAsync.when(
              data: (papers) {
                final paperBySlot = <String, Paper>{
                  for (final p in papers) '${p.phaseId}::${p.subjectId}': p,
                };
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final phase in phases) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          phase.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ...subjects.map((subject) {
                        final paper = paperBySlot['${phase.id}::${subject.id}'];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(subject.name),
                            trailing: paper != null
                                ? PaperStatusBadge(paper: paper)
                                : const _MissingSourceBadge(),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
              loading: () => const LoadingList(),
              error: (e, st) => ErrorState(message: e.toString()),
            ),
            loading: () => const LoadingList(),
            error: (e, st) => ErrorState(message: e.toString()),
          ),
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(message: e.toString()),
        ),
      ),
    );
  }
}

class _MissingSourceBadge extends StatelessWidget {
  const _MissingSourceBadge();

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: const Text('Missing Source', style: TextStyle(fontSize: 11)),
      backgroundColor: Colors.red.withValues(alpha: 0.12),
      side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}
