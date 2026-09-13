import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pagination/paginated_result.dart';
import '../../core/pagination/pagination_notifier.dart';
import '../../core/pagination/pagination_state.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/validation/paper_status.dart';
import '../../data/models/paper.dart';
import '../../data/models/paper_section.dart';
import '../../data/models/question.dart';

/// Papers are structurally capped at 24 rows (one per phase/subject slot
/// — see CLAUDE.md "Database Rules"), so this stays a plain, unpaginated
/// fetch: adding pagination to a table that can never exceed 24 rows
/// would add complexity with no real benefit. See
/// docs/PERFORMANCE_AUDIT.md "Papers list — deliberately not paginated".
final adminAllPapersProvider = FutureProvider<List<Paper>>((ref) {
  return ref.read(adminRepositoryProvider).getAllPapers();
});

final adminSectionsProvider = FutureProvider.family<List<PaperSection>, String>((ref, paperId) {
  return ref.read(adminRepositoryProvider).getSections(paperId);
});

final adminQuestionsProvider = FutureProvider.family<List<Question>, String>((ref, sectionId) {
  return ref.read(adminRepositoryProvider).getQuestions(sectionId);
});

final adminQuestionProvider = FutureProvider.family<Question, String>((ref, questionId) {
  return ref.read(adminRepositoryProvider).getQuestion(questionId);
});

/// Keyset-paginated review queue — see docs/PERFORMANCE_AUDIT.md for why
/// this replaced a single unbounded fetch of every questionable question
/// in the database.
class AdminQuestionableQuestionsNotifier extends PaginationNotifier<Question> {
  @override
  Future<PaginatedResult<Question>> fetchPage(String? cursor, int limit) {
    return ref.read(adminRepositoryProvider).getQuestionableQuestionsPage(cursor: cursor, limit: limit);
  }
}

final adminQuestionableQuestionsProvider =
    NotifierProvider<AdminQuestionableQuestionsNotifier, PaginationState<Question>>(
  AdminQuestionableQuestionsNotifier.new,
);

final adminPaperContentProvider =
    FutureProvider.family<List<SectionQuestions>, String>((ref, paperId) {
  return ref.read(adminRepositoryProvider).getPaperContent(paperId);
});
