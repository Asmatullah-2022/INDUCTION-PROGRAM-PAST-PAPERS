import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/services/downloads_service.dart';
import 'package:induction_program_past_papers/data/models/download_record.dart';

DownloadRecord _record({
  String paperId = 'paper-1',
  DownloadDocumentType type = DownloadDocumentType.mcqAnswerKey,
  DateTime? downloadedAt,
  int fileSizeBytes = 1000,
}) {
  return DownloadRecord(
    paperId: paperId,
    documentType: type,
    paperTitle: 'Test Paper',
    phaseName: 'Phase II',
    subjectName: 'English',
    filePath: '/tmp/$paperId-${type.dbValue}.pdf',
    fileSizeBytes: fileSizeBytes,
    downloadedAt: downloadedAt ?? DateTime(2024, 1, 1),
    contentStatus: 'PUBLISHED',
  );
}

void main() {
  group('DownloadRecord — id and JSON round-trip', () {
    test('id combines paperId and document type, so one paper can have one record per type', () {
      final mcq = _record(type: DownloadDocumentType.mcqAnswerKey);
      final short = _record(type: DownloadDocumentType.solvedShort);
      expect(mcq.id, isNot(short.id));
      expect(mcq.id, contains('paper-1'));
      expect(mcq.id, contains('MCQ_ANSWER_KEY'));
    });

    test('toJson/fromJson round-trips every field exactly', () {
      final original = _record();
      final restored = DownloadRecord.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.paperTitle, original.paperTitle);
      expect(restored.phaseName, original.phaseName);
      expect(restored.subjectName, original.subjectName);
      expect(restored.filePath, original.filePath);
      expect(restored.fileSizeBytes, original.fileSizeBytes);
      expect(restored.downloadedAt, original.downloadedAt);
      expect(restored.contentStatus, original.contentStatus);
    });

    test('an unrecognized document_type value throws rather than silently mislabeling', () {
      final json = _record().toJson();
      json['document_type'] = 'NOT_A_REAL_TYPE';
      expect(() => DownloadRecord.fromJson(json), throwsArgumentError);
    });
  });

  group('DownloadDocumentTypeX — labels', () {
    test('every document type has a non-empty label and a unique dbValue', () {
      final dbValues = DownloadDocumentType.values.map((t) => t.dbValue).toSet();
      expect(dbValues.length, DownloadDocumentType.values.length);
      for (final type in DownloadDocumentType.values) {
        expect(type.label, isNotEmpty);
      }
    });

    test('fromDbValue is the exact inverse of dbValue for every type', () {
      for (final type in DownloadDocumentType.values) {
        expect(DownloadDocumentTypeX.fromDbValue(type.dbValue), type);
      }
    });
  });

  group('DownloadsService.upsert — duplicate-download prevention', () {
    test('downloading the same paper/type again replaces the old record, not duplicates it', () {
      final first = _record(downloadedAt: DateTime(2024, 1, 1), fileSizeBytes: 1000);
      final second = _record(downloadedAt: DateTime(2024, 6, 1), fileSizeBytes: 2000);

      var records = DownloadsService.upsert(const [], first);
      expect(records.length, 1);

      records = DownloadsService.upsert(records, second);
      expect(records.length, 1); // still one entry, not two
      expect(records.single.fileSizeBytes, 2000); // the newer download won
    });

    test('a different document type for the same paper is a separate record', () {
      final mcq = _record(type: DownloadDocumentType.mcqAnswerKey);
      final complete = _record(type: DownloadDocumentType.completeSolvedPaper);

      var records = DownloadsService.upsert(const [], mcq);
      records = DownloadsService.upsert(records, complete);

      expect(records.length, 2);
    });

    test('a different paper with the same document type is a separate record', () {
      final paperA = _record(paperId: 'paper-a');
      final paperB = _record(paperId: 'paper-b');

      var records = DownloadsService.upsert(const [], paperA);
      records = DownloadsService.upsert(records, paperB);

      expect(records.length, 2);
    });
  });

  group('DownloadsService.formatFileSize', () {
    test('formats bytes, kilobytes, and megabytes at the expected thresholds', () {
      expect(DownloadsService.formatFileSize(500), '500 B');
      expect(DownloadsService.formatFileSize(2048), '2 KB');
      expect(DownloadsService.formatFileSize(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
