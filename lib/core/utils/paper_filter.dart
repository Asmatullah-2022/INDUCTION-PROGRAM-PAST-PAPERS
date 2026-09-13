import '../../data/models/paper.dart';

enum PaperSortOrder { newest, oldest, titleAsc }

/// Pure client-side search/filter/sort over an already-fetched paper list
/// (the admin papers list is at most 24 rows, so there's no need for a
/// server-side query per filter change). Kept here, outside the widget,
/// so it's directly unit-testable — see test/unit/paper_filter_test.dart.
class PaperFilter {
  PaperFilter._();

  static List<Paper> apply({
    required List<Paper> papers,
    String query = '',
    String? phaseId,
    String? subjectId,
    String? contentStatus,
    PaperSortOrder sortOrder = PaperSortOrder.newest,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    var result = papers.where((p) {
      if (phaseId != null && p.phaseId != phaseId) return false;
      if (subjectId != null && p.subjectId != subjectId) return false;
      if (contentStatus != null && p.contentStatus != contentStatus) return false;
      if (normalizedQuery.isNotEmpty &&
          !p.title.toLowerCase().contains(normalizedQuery) &&
          !(p.cadre?.toLowerCase().contains(normalizedQuery) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    switch (sortOrder) {
      case PaperSortOrder.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case PaperSortOrder.oldest:
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case PaperSortOrder.titleAsc:
        result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return result;
  }
}
