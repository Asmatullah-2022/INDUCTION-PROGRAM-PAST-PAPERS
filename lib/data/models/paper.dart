/// A single paper under Phase -> Subject. Deliberately has NO year field —
/// papers are identified only by phase + subject (+ optional cadre), per
/// the app's no-year content rule.
class Paper {
  final String id;
  final String phaseId;
  final String subjectId;
  final String title;
  final String? cadre;
  final int? totalMarks;
  final int? durationMinutes;
  final String? sourceFileUrl;
  final String? sourceFileType;
  final String contentStatus;
  final String verificationStatus;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? verificationNotes;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Paper({
    required this.id,
    required this.phaseId,
    required this.subjectId,
    required this.title,
    this.cadre,
    this.totalMarks,
    this.durationMinutes,
    this.sourceFileUrl,
    this.sourceFileType,
    required this.contentStatus,
    required this.verificationStatus,
    this.verifiedBy,
    this.verifiedAt,
    this.verificationNotes,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPublished => contentStatus == 'PUBLISHED';

  factory Paper.fromJson(Map<String, dynamic> json) => Paper(
        id: json['id'] as String,
        phaseId: json['phase_id'] as String,
        subjectId: json['subject_id'] as String,
        title: json['title'] as String,
        cadre: json['cadre'] as String?,
        totalMarks: (json['total_marks'] as num?)?.toInt(),
        durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
        sourceFileUrl: json['source_file_url'] as String?,
        sourceFileType: json['source_file_type'] as String?,
        contentStatus: json['content_status'] as String? ?? 'DRAFT',
        verificationStatus: json['verification_status'] as String? ?? 'DRAFT',
        verifiedBy: json['verified_by'] as String?,
        verifiedAt: json['verified_at'] != null
            ? DateTime.parse(json['verified_at'] as String)
            : null,
        verificationNotes: json['verification_notes'] as String?,
        version: (json['version'] as num?)?.toInt() ?? 1,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phase_id': phaseId,
        'subject_id': subjectId,
        'title': title,
        'cadre': cadre,
        'total_marks': totalMarks,
        'duration_minutes': durationMinutes,
        'source_file_url': sourceFileUrl,
        'source_file_type': sourceFileType,
        'content_status': contentStatus,
        'verification_status': verificationStatus,
        'verified_by': verifiedBy,
        'verified_at': verifiedAt?.toIso8601String(),
        'verification_notes': verificationNotes,
        'version': version,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
