/// Which generated/original document a [DownloadRecord] points at. Kept
/// as an explicit enum (not a free-text string) so a new document type
/// can never be introduced by a typo in a repository call.
enum DownloadDocumentType {
  originalPaper,
  mcqAnswerKey,
  solvedShort,
  solvedLong,
  completeSolvedPaper,
}

extension DownloadDocumentTypeX on DownloadDocumentType {
  String get dbValue {
    switch (this) {
      case DownloadDocumentType.originalPaper:
        return 'ORIGINAL_PAPER';
      case DownloadDocumentType.mcqAnswerKey:
        return 'MCQ_ANSWER_KEY';
      case DownloadDocumentType.solvedShort:
        return 'SOLVED_SHORT';
      case DownloadDocumentType.solvedLong:
        return 'SOLVED_LONG';
      case DownloadDocumentType.completeSolvedPaper:
        return 'COMPLETE_SOLVED_PAPER';
    }
  }

  String get label {
    switch (this) {
      case DownloadDocumentType.originalPaper:
        return 'Original Paper';
      case DownloadDocumentType.mcqAnswerKey:
        return 'MCQ Answer Key';
      case DownloadDocumentType.solvedShort:
        return 'Solved Short Questions';
      case DownloadDocumentType.solvedLong:
        return 'Solved Long Questions';
      case DownloadDocumentType.completeSolvedPaper:
        return 'Complete Solved Paper';
    }
  }

  static DownloadDocumentType fromDbValue(String value) {
    switch (value) {
      case 'ORIGINAL_PAPER':
        return DownloadDocumentType.originalPaper;
      case 'MCQ_ANSWER_KEY':
        return DownloadDocumentType.mcqAnswerKey;
      case 'SOLVED_SHORT':
        return DownloadDocumentType.solvedShort;
      case 'SOLVED_LONG':
        return DownloadDocumentType.solvedLong;
      case 'COMPLETE_SOLVED_PAPER':
        return DownloadDocumentType.completeSolvedPaper;
      default:
        throw ArgumentError('Unknown download document type: $value');
    }
  }
}

/// One locally-saved file the Downloads screen lists — always produced
/// from content the user was already authorized to view (a generated PDF
/// built from data already fetched under RLS, or a PUBLISHED paper's own
/// source file). Never a separate authorization path of its own; see
/// DownloadsService.
class DownloadRecord {
  final String paperId;
  final DownloadDocumentType documentType;
  final String paperTitle;
  final String phaseName;
  final String subjectName;
  final String filePath;
  final int fileSizeBytes;
  final DateTime downloadedAt;

  /// The paper's content_status at the moment of download (e.g.
  /// "PUBLISHED") — display-only, so a downloaded file's card can show
  /// the same verification context the user saw when they downloaded it.
  final String contentStatus;

  const DownloadRecord({
    required this.paperId,
    required this.documentType,
    required this.paperTitle,
    required this.phaseName,
    required this.subjectName,
    required this.filePath,
    required this.fileSizeBytes,
    required this.downloadedAt,
    required this.contentStatus,
  });

  /// Identifies "the same download" for de-duplication — one paper can
  /// have at most one saved file per document type; downloading again
  /// overwrites it rather than creating a second entry.
  String get id => '${paperId}_${documentType.dbValue}';

  factory DownloadRecord.fromJson(Map<String, dynamic> json) => DownloadRecord(
        paperId: json['paper_id'] as String,
        documentType: DownloadDocumentTypeX.fromDbValue(json['document_type'] as String),
        paperTitle: json['paper_title'] as String,
        phaseName: json['phase_name'] as String,
        subjectName: json['subject_name'] as String,
        filePath: json['file_path'] as String,
        fileSizeBytes: (json['file_size_bytes'] as num).toInt(),
        downloadedAt: DateTime.parse(json['downloaded_at'] as String),
        contentStatus: json['content_status'] as String? ?? 'PUBLISHED',
      );

  Map<String, dynamic> toJson() => {
        'paper_id': paperId,
        'document_type': documentType.dbValue,
        'paper_title': paperTitle,
        'phase_name': phaseName,
        'subject_name': subjectName,
        'file_path': filePath,
        'file_size_bytes': fileSizeBytes,
        'downloaded_at': downloadedAt.toIso8601String(),
        'content_status': contentStatus,
      };
}
