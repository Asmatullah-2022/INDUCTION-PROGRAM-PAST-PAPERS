import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/pdf_export_service.dart';
import '../../data/models/paper_section.dart';
import '../../data/models/question.dart';
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
      appBar: AppBar(
        title: const Text('Short Questions & Answers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export as PDF',
            onPressed: sectionsAsync.maybeWhen(
              data: (sections) {
                final shorts = sections
                    .expand((s) => s.questions)
                    .where((q) => q.questionType == QuestionType.short)
                    .toList()
                  ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
                if (shorts.isEmpty) return null;
                return () => _exportPdf(ref, shorts);
              },
              orElse: () => null,
            ),
          ),
        ],
      ),
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
            itemBuilder: (context, index) =>
                QuestionTile(question: shorts[index], paperId: paperId),
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

  Future<void> _exportPdf(WidgetRef ref, List<Question> shorts) async {
    final paper = await ref.read(paperByIdProvider(paperId).future);
    final names = await ref.read(paperPhaseSubjectNamesProvider(paperId).future);
    await PdfExportService.shareDocument(
      paper: paper,
      phaseName: names.phaseName,
      subjectName: names.subjectName,
      documentTitle: 'Solved Short Questions',
      sections: [
        (
          section: PaperSection(
            id: 'export-short',
            paperId: paperId,
            sectionName: 'Short Questions & Answers',
            sectionCode: '',
            displayOrder: 0,
          ),
          questions: shorts,
        ),
      ],
    );
  }
}
