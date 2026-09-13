import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/pdf_export_service.dart';
import '../../data/models/paper_section.dart';
import '../../data/models/question.dart';
import '../../shared/widgets/question_tile.dart';
import '../../shared/widgets/state_widgets.dart';
import 'papers_providers.dart';

class LongAnswersScreen extends ConsumerWidget {
  final String paperId;
  const LongAnswersScreen({super.key, required this.paperId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(paperSectionsProvider(paperId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Long Questions & Answers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export as PDF',
            onPressed: sectionsAsync.maybeWhen(
              data: (sections) {
                final longs = sections
                    .expand((s) => s.questions)
                    .where((q) => q.questionType == QuestionType.long)
                    .toList()
                  ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
                if (longs.isEmpty) return null;
                return () => _exportPdf(ref, longs);
              },
              orElse: () => null,
            ),
          ),
        ],
      ),
      body: sectionsAsync.when(
        data: (sections) {
          final longs = sections
              .expand((s) => s.questions)
              .where((q) => q.questionType == QuestionType.long)
              .toList()
            ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));

          if (longs.isEmpty) {
            return const EmptyState(
              icon: Icons.notes_outlined,
              title: 'No long questions available for this paper yet',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: longs.length,
            itemBuilder: (context, index) => QuestionTile(question: longs[index]),
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

  Future<void> _exportPdf(WidgetRef ref, List<Question> longs) async {
    final paper = await ref.read(paperByIdProvider(paperId).future);
    final names = await ref.read(paperPhaseSubjectNamesProvider(paperId).future);
    await PdfExportService.shareDocument(
      paper: paper,
      phaseName: names.phaseName,
      subjectName: names.subjectName,
      documentTitle: 'Solved Long Questions',
      sections: [
        (
          section: PaperSection(
            id: 'export-long',
            paperId: paperId,
            sectionName: 'Long Questions & Answers',
            sectionCode: '',
            displayOrder: 0,
          ),
          questions: longs,
        ),
      ],
    );
  }
}
