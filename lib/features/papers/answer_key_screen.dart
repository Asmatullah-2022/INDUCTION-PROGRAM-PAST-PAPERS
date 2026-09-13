import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/pdf_export_service.dart';
import '../../data/models/paper_section.dart';
import '../../data/models/question.dart';
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
      appBar: AppBar(
        title: const Text('MCQ Answer Key'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export as PDF',
            onPressed: sectionsAsync.maybeWhen(
              data: (sections) {
                final mcqs = sections
                    .expand((s) => s.questions)
                    .where((q) => q.questionType == QuestionType.mcq)
                    .toList()
                  ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
                if (mcqs.isEmpty) return null;
                return () => _exportPdf(ref, mcqs);
              },
              orElse: () => null,
            ),
          ),
        ],
      ),
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
            itemBuilder: (context, index) =>
                QuestionTile(question: mcqs[index], paperId: paperId),
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

  Future<void> _exportPdf(WidgetRef ref, List<Question> mcqs) async {
    final paper = await ref.read(paperByIdProvider(paperId).future);
    final names = await ref.read(paperPhaseSubjectNamesProvider(paperId).future);
    await PdfExportService.shareDocument(
      paper: paper,
      phaseName: names.phaseName,
      subjectName: names.subjectName,
      documentTitle: 'MCQ Answer Key',
      sections: [
        (
          section: PaperSection(
            id: 'export-mcq',
            paperId: paperId,
            sectionName: 'MCQ Answer Key',
            sectionCode: '',
            displayOrder: 0,
          ),
          questions: mcqs,
        ),
      ],
    );
  }
}
