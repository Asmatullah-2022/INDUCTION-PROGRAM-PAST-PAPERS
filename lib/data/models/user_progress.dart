class UserProgress {
  final String id;
  final String userId;
  final String phaseId;
  final String subjectId;
  final int attemptedCount;
  final int correctCount;
  final int incorrectCount;
  final int completedPapersCount;
  final DateTime updatedAt;

  const UserProgress({
    required this.id,
    required this.userId,
    required this.phaseId,
    required this.subjectId,
    required this.attemptedCount,
    required this.correctCount,
    required this.incorrectCount,
    required this.completedPapersCount,
    required this.updatedAt,
  });

  double get accuracyPercentage =>
      attemptedCount == 0 ? 0 : (correctCount / attemptedCount) * 100;

  factory UserProgress.fromJson(Map<String, dynamic> json) => UserProgress(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        phaseId: json['phase_id'] as String,
        subjectId: json['subject_id'] as String,
        attemptedCount: (json['attempted_count'] as num?)?.toInt() ?? 0,
        correctCount: (json['correct_count'] as num?)?.toInt() ?? 0,
        incorrectCount: (json['incorrect_count'] as num?)?.toInt() ?? 0,
        completedPapersCount: (json['completed_papers_count'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'phase_id': phaseId,
        'subject_id': subjectId,
        'attempted_count': attemptedCount,
        'correct_count': correctCount,
        'incorrect_count': incorrectCount,
        'completed_papers_count': completedPapersCount,
        'updated_at': updatedAt.toIso8601String(),
      };
}
