import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/data/models/download_record.dart';
import 'package:induction_program_past_papers/features/downloads/downloads_providers.dart';
import 'package:induction_program_past_papers/features/downloads/downloads_screen.dart';

/// Overrides state management only (no CacheService/SharedPreferences,
/// no real filesystem I/O) — [delete] is overridden too so a tap on
/// Delete never falls through to the real DownloadsService, matching
/// the fake-repository pattern used throughout this test suite (see
/// ai_teacher_screen_test.dart) rather than mocking platform channels.
class _FakeDownloadsNotifier extends DownloadsNotifier {
  final List<DownloadRecord> initial;
  _FakeDownloadsNotifier(this.initial);

  @override
  List<DownloadRecord> build() => initial;

  @override
  Future<void> delete(DownloadRecord record) async {
    state = state.where((r) => r.id != record.id).toList();
  }
}

DownloadRecord _record({
  String paperId = 'paper-1',
  DownloadDocumentType type = DownloadDocumentType.mcqAnswerKey,
}) {
  return DownloadRecord(
    paperId: paperId,
    documentType: type,
    paperTitle: 'Sample Paper Title',
    phaseName: 'Phase II',
    subjectName: 'English',
    // Deliberately a path that cannot exist, so every test exercises the
    // "file missing" state deterministically without touching real I/O.
    filePath: '/nonexistent/$paperId-${type.dbValue}.pdf',
    fileSizeBytes: 51200,
    downloadedAt: DateTime(2024, 3, 1, 10, 30),
    contentStatus: 'PUBLISHED',
  );
}

Widget _wrap(List<DownloadRecord> records) {
  return ProviderScope(
    overrides: [
      downloadsProvider.overrideWith(() => _FakeDownloadsNotifier(records)),
    ],
    child: const MaterialApp(home: DownloadsScreen()),
  );
}

void main() {
  group('DownloadsScreen — empty state', () {
    testWidgets('shows the empty state when there are no downloads', (tester) async {
      await tester.pumpWidget(_wrap(const []));
      await tester.pumpAndSettle();

      expect(find.text('No downloads yet'), findsOneWidget);
    });
  });

  group('DownloadsScreen — populated list', () {
    testWidgets('shows paper title, phase/subject, document type, size, and date', (tester) async {
      await tester.pumpWidget(_wrap([_record()]));
      await tester.pumpAndSettle();

      expect(find.text('Sample Paper Title'), findsOneWidget);
      expect(find.text('Phase II • English'), findsOneWidget);
      expect(find.text('MCQ Answer Key'), findsOneWidget);
      expect(find.text('50 KB'), findsOneWidget);
      expect(find.text('PUBLISHED'), findsOneWidget);
    });

    testWidgets('a record whose file no longer exists shows the missing-file warning and disables Open/Share',
        (tester) async {
      await tester.pumpWidget(_wrap([_record()]));
      await tester.pumpAndSettle();

      expect(find.text('File missing or was removed from device storage'), findsOneWidget);

      // Tapping Open on a missing file must be a no-op (button disabled),
      // not an attempt to read a nonexistent path.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('File missing or was removed from device storage'), findsOneWidget);
    });

    testWidgets('deleting a record removes it from the list after confirmation', (tester) async {
      await tester.pumpWidget(_wrap([_record()]));
      await tester.pumpAndSettle();
      expect(find.text('Sample Paper Title'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete download?'), findsOneWidget);

      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('Sample Paper Title'), findsNothing);
      expect(find.text('No downloads yet'), findsOneWidget);
    });

    testWidgets('two different document types for the same paper both appear as separate entries',
        (tester) async {
      await tester.pumpWidget(_wrap([
        _record(type: DownloadDocumentType.mcqAnswerKey),
        _record(type: DownloadDocumentType.completeSolvedPaper),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('MCQ Answer Key'), findsOneWidget);
      expect(find.text('Complete Solved Paper'), findsOneWidget);
    });
  });
}
