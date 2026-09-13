import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/widgets/question_tile.dart';
import '../../shared/widgets/state_widgets.dart';
import 'papers_providers.dart';

class AnswerKeyScreen extends ConsumerWidget {
  final String paperId;
  const AnswerKeyScreen({super.key, required this.paperId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(paperSectionsProvider(paperId));

    return Scaffold(
      appBar: AppBar(title: const Text('MCQ Answer Key')),
      body: sectionsAsync.when(
        data: (sections) {
          final mcqs = sections
              .expand((s) => s.questions)
              .where((q) => q.questionType == QuestionType.mcq)
              .toList()
            ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));

          if (mcqs.isEmpty) {
            return const EmptyState(
              icon: Icons.quiz_outlined,
              title: 'No MCQs available for this paper yet',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: mcqs.length,
            itemBuilder: (context, index) => QuestionTile(question: mcqs[index]),
          );
        },
        loading: () => const LoadingList(),
        error: (e, st) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(paperSectionsProvider(paperId)),
        ),
      ),
    );
  }
}
