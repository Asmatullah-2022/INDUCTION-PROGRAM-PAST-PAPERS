import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/widgets/question_tile.dart';
import '../../shared/widgets/state_widgets.dart';
import 'papers_providers.dart';

class ShortAnswersScreen extends ConsumerWidget {
  final String paperId;
  const ShortAnswersScreen({super.key, required this.paperId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(paperSectionsProvider(paperId));

    return Scaffold(
      appBar: AppBar(title: const Text('Short Questions & Answers')),
      body: sectionsAsync.when(
        data: (sections) {
          final shorts = sections
              .expand((s) => s.questions)
              .where((q) => q.questionType == QuestionType.short)
              .toList()
            ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));

          if (shorts.isEmpty) {
            return const EmptyState(
              icon: Icons.short_text_outlined,
              title: 'No short questions available for this paper yet',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: shorts.length,
            itemBuilder: (context, index) => QuestionTile(question: shorts[index]),
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
