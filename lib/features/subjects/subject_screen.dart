import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/paper.dart';
import '../../shared/widgets/state_widgets.dart';

final papersForSubjectProvider =
    FutureProvider.family<List<Paper>, ({String phaseId, String subjectId})>(
  (ref, args) => ref
      .read(paperRepositoryProvider)
      .getPapersForSubject(phaseId: args.phaseId, subjectId: args.subjectId),
);

class SubjectScreen extends ConsumerWidget {
  final String subjectId;
  final String phaseId;

  const SubjectScreen({super.key, required this.subjectId, required this.phaseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final papersAsync =
        ref.watch(papersForSubjectProvider((phaseId: phaseId, subjectId: subjectId)));

    return Scaffold(
      appBar: AppBar(title: const Text('Papers')),
      body: papersAsync.when(
        data: (papers) {
          if (papers.isEmpty) {
            return const EmptyState(
              icon: Icons.description_outlined,
              title: 'No verified papers available yet.',
              subtitle:
                  'MISSING SOURCE PAPER — this paper has not been published for this phase/subject yet.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: papers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final paper = papers[index];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/paper/${paper.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(paper.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        if (paper.cadre != null) ...[
                          const SizedBox(height: 4),
                          Text(paper.cadre!,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (paper.totalMarks != null)
                              Chip(label: Text('${paper.totalMarks} marks')),
                            if (paper.durationMinutes != null)
                              Chip(label: Text('${paper.durationMinutes} min')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const LoadingList(itemCount: 1),
        error: (e, st) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(
              papersForSubjectProvider((phaseId: phaseId, subjectId: subjectId))),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/practice/setup?phaseId=$phaseId&subjectId=$subjectId'),
        icon: const Icon(Icons.quiz_outlined),
        label: const Text('Practice MCQs'),
      ),
    );
  }
}
