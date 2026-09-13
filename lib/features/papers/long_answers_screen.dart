import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/downloads_service.dart';
import '../../core/services/pdf_export_service.dart';
import '../../data/models/download_record.dart';
import '../../data/models/paper_section.dart';
import '../../data/models/question.dart';
import '../../shared/widgets/question_tile.dart';
import '../../shared/widgets/state_widgets.dart';
import '../downloads/downloads_providers.dart';
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
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download PDF',
            onPressed: sectionsAsync.maybeWhen(
              data: (sections) {
                final longs = sections
                    .expand((s) => s.questions)
                    .where((q) => q.questionType == QuestionType.long)
                    .toList()
                  ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
                if (longs.isEmpty) return null;
                return () => _downloadPdf(context, ref, longs);
              },
              orElse: () => null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share as PDF',
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
            itemBuilder: (context, index) =>
                QuestionTile(question: longs[index], paperId: paperId),
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

  Future<void> _downloadPdf(BuildContext context, WidgetRef ref, List<Question> longs) async {
    final paper = await ref.read(paperByIdProvider(paperId).future);
    final names = await ref.read(paperPhaseSubjectNamesProvider(paperId).future);
    try {
      await DownloadsService.downloadGeneratedPdf(
        paper: paper,
        phaseName: names.phaseName,
        subjectName: names.subjectName,
        documentType: DownloadDocumentType.solvedLong,
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
      ref.read(downloadsProvider.notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved to Downloads'),
            action: SnackBarAction(label: 'View', onPressed: () => context.push('/downloads')),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }
}
