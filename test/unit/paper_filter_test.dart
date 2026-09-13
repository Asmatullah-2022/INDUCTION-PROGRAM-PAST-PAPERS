import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/utils/paper_filter.dart';
import 'package:induction_program_past_papers/data/models/paper.dart';

Paper _paper({
  required String id,
  required String title,
  String phaseId = 'phase-1',
  String subjectId = 'subject-1',
  String contentStatus = 'DRAFT',
  DateTime? createdAt,
  String? cadre,
}) {
  final now = createdAt ?? DateTime(2026, 1, 1);
  return Paper(
    id: id,
    phaseId: phaseId,
    subjectId: subjectId,
    title: title,
    cadre: cadre,
    contentStatus: contentStatus,
    verificationStatus: contentStatus,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('PaperFilter.apply — filtering', () {
    final papers = [
      _paper(id: '1', title: 'English Phase II', phaseId: 'ph2', subjectId: 'eng', contentStatus: 'PUBLISHED'),
      _paper(id: '2', title: 'Mathematics Phase III', phaseId: 'ph3', subjectId: 'math', contentStatus: 'DRAFT'),
      _paper(id: '3', title: 'English Phase IV', phaseId: 'ph4', subjectId: 'eng', contentStatus: 'VERIFIED'),
    ];

    test('with no filters returns everything', () {
      expect(PaperFilter.apply(papers: papers).length, 3);
    });

    test('filters by phase', () {
      final result = PaperFilter.apply(papers: papers, phaseId: 'ph2');
      expect(result.map((p) => p.id), ['1']);
    });

    test('filters by subject', () {
      final result = PaperFilter.apply(papers: papers, subjectId: 'eng');
      expect(result.map((p) => p.id), containsAll(['1', '3']));
      expect(result.length, 2);
    });

    test('filters by content status', () {
      final result = PaperFilter.apply(papers: papers, contentStatus: 'DRAFT');
      expect(result.map((p) => p.id), ['2']);
    });

    test('search query matches title case-insensitively', () {
      final result = PaperFilter.apply(papers: papers, query: 'english');
      expect(result.length, 2);
    });

    test('search query matches cadre too', () {
      final withCadre = [
        ...papers,
        _paper(id: '4', title: 'Untitled', cadre: 'Senior Cadre'),
      ];
      final result = PaperFilter.apply(papers: withCadre, query: 'senior');
      expect(result.map((p) => p.id), ['4']);
    });

    test('combining filters narrows further', () {
      final result =
          PaperFilter.apply(papers: papers, subjectId: 'eng', contentStatus: 'PUBLISHED');
      expect(result.map((p) => p.id), ['1']);
    });

    test('no matches returns an empty list, not an error', () {
      final result = PaperFilter.apply(papers: papers, query: 'nonexistent subject matter');
      expect(result, isEmpty);
    });
  });

  group('PaperFilter.apply — sorting', () {
    final papers = [
      _paper(id: 'a', title: 'Zebra Paper', createdAt: DateTime(2026, 1, 1)),
      _paper(id: 'b', title: 'Apple Paper', createdAt: DateTime(2026, 3, 1)),
      _paper(id: 'c', title: 'Mango Paper', createdAt: DateTime(2026, 2, 1)),
    ];

    test('newest sorts by createdAt descending', () {
      final result = PaperFilter.apply(papers: papers, sortOrder: PaperSortOrder.newest);
      expect(result.map((p) => p.id), ['b', 'c', 'a']);
    });

    test('oldest sorts by createdAt ascending', () {
      final result = PaperFilter.apply(papers: papers, sortOrder: PaperSortOrder.oldest);
      expect(result.map((p) => p.id), ['a', 'c', 'b']);
    });

    test('titleAsc sorts alphabetically case-insensitively', () {
      final result = PaperFilter.apply(papers: papers, sortOrder: PaperSortOrder.titleAsc);
      expect(result.map((p) => p.id), ['b', 'c', 'a']);
    });
  });
}
