import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/pdf_export_service.dart';
import '../../core/utils/debouncer.dart';
import '../../data/repositories/paper_repository.dart' show SectionWithQuestions;
import '../../shared/widgets/question_tile.dart';
import '../../shared/widgets/state_widgets.dart';
import 'papers_providers.dart';

class CompleteSolutionScreen extends ConsumerStatefulWidget {
  final String paperId;
  const CompleteSolutionScreen({super.key, required this.paperId});

  @override
  ConsumerState<CompleteSolutionScreen> createState() => _CompleteSolutionScreenState();
}

class _CompleteSolutionScreenState extends ConsumerState<CompleteSolutionScreen> {
  final _searchController = TextEditingController();
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 300));
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sectionsAsync = ref.watch(paperSectionsProvider(widget.paperId));
    final paperAsync = ref.watch(paperByIdProvider(widget.paperId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Solved Paper'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export as PDF',
            onPressed: sectionsAsync.maybeWhen(
              data: (sections) => sections.isEmpty ? null : () => _exportPdf(sections),
              orElse: () => null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              final title = paperAsync.maybeWhen(data: (p) => p.title, orElse: () => 'Paper');
              Share.share(
                'Check out "$title" solved paper on Induction Program Past Papers.',
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search within this paper',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (value) => _debouncer.run(() => setState(() => _query = value)),
            ),
          ),
        ),
      ),
      body: sectionsAsync.when(
        data: (sections) {
          final filtered = sections.map((s) {
            final questions = s.questions.where((q) {
              if (_query.trim().isEmpty) return true;
              final lower = _query.toLowerCase();
              return q.questionText.toLowerCase().contains(lower) ||
                  (q.explanation?.toLowerCase().contains(lower) ?? false);
            }).toList()
              ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
            return (section: s.section, questions: questions);
          }).where((s) => s.questions.isNotEmpty).toList();

          if (filtered.isEmpty) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'No matching questions found',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            itemBuilder: (context, sIndex) {
              final entry = filtered[sIndex];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${entry.section.sectionName}'
                      '${entry.section.marks != null ? " (${entry.section.marks} marks)" : ""}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ...entry.questions.map((q) => QuestionTile(question: q, paperId: widget.paperId)),
                ],
              );
            },
          );
        },
        loading: () => const LoadingList(),
        error: (e, st) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(paperSectionsProvider(widget.paperId)),
        ),
      ),
    );
  }

  Future<void> _exportPdf(List<SectionWithQuestions> sections) async {
    final paper = await ref.read(paperByIdProvider(widget.paperId).future);
    final names = await ref.read(paperPhaseSubjectNamesProvider(widget.paperId).future);
    await PdfExportService.shareDocument(
      paper: paper,
      phaseName: names.phaseName,
      subjectName: names.subjectName,
      documentTitle: 'Complete Solved Paper',
      sections: [
        for (final s in sections) (section: s.section, questions: s.questions),
      ],
    );
  }
}
