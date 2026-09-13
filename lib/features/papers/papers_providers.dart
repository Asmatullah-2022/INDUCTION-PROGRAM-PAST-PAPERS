import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/paper.dart';
import '../../data/repositories/paper_repository.dart';
import '../home/home_providers.dart';
import '../phases/phase_screen.dart' show subjectsProvider;

final paperByIdProvider = FutureProvider.family<Paper, String>(
  (ref, paperId) => ref.read(paperRepositoryProvider).getPaper(paperId),
);

final paperSectionsProvider =
    FutureProvider.family<List<SectionWithQuestions>, String>(
  (ref, paperId) =>
      ref.read(paperRepositoryProvider).getSectionsWithQuestions(paperId),
);

/// (phaseName, subjectName) for a paper — used to label generated PDFs
/// and any other place that needs a human-readable phase/subject without
/// re-fetching the whole phase/subject list inline.
final paperPhaseSubjectNamesProvider =
    FutureProvider.family<({String phaseName, String subjectName}), String>(
  (ref, paperId) async {
    final paper = await ref.watch(paperByIdProvider(paperId).future);
    final phases = await ref.watch(phasesProvider.future);
    final subjects = await ref.watch(subjectsProvider.future);
    final phaseName = phases.where((p) => p.id == paper.phaseId).map((p) => p.name).firstOrNull ??
        'Unknown Phase';
    final subjectName =
        subjects.where((s) => s.id == paper.subjectId).map((s) => s.name).firstOrNull ??
            'Unknown Subject';
    return (phaseName: phaseName, subjectName: subjectName);
  },
);

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
