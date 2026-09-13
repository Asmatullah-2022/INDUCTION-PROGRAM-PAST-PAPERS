import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/repository_providers.dart';
import '../../shared/widgets/quality_badge.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';
import 'admin_providers.dart';

class AdminQuestionsScreen extends ConsumerWidget {
  final String paperId;
  final String sectionId;
  const AdminQuestionsScreen({super.key, required this.paperId, required this.sectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(adminQuestionsProvider(sectionId));

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Questions')),
        body: questionsAsync.when(
          data: (questions) {
            if (questions.isEmpty) {
              return const EmptyState(
                icon: Icons.quiz_outlined,
                title: 'No questions in this section yet',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: questions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final question = questions[index];
                return Card(
                  child: ListTile(
                    title: Text('Q${question.questionNumber}. ${question.questionText}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Row(
                      children: [
                        Text(question.questionType.dbValue.toUpperCase()),
                        const SizedBox(width: 8),
                        QualityBadge(status: question.qualityStatus, note: question.qualityNote),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(context, ref, question.id),
                    ),
                    onTap: () => context.push(
                      '/admin/papers/$paperId/sections/$sectionId/questions/${question.id}',
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(adminQuestionsProvider(sectionId)),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () =>
              context.push('/admin/papers/$paperId/sections/$sectionId/questions/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String questionId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Question'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(adminRepositoryProvider).deleteQuestion(questionId);
              ref.invalidate(adminQuestionsProvider(sectionId));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
