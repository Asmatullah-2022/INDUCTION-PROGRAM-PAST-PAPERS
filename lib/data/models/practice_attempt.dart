class PracticeAnswer {
  final String id;
  final String attemptId;
  final String questionId;
  final String? selectedOptionLabel;
  final bool isCorrect;
  final bool isSkipped;

  const PracticeAnswer({
    required this.id,
    required this.attemptId,
    required this.questionId,
    this.selectedOptionLabel,
    required this.isCorrect,
    required this.isSkipped,
  });

  factory PracticeAnswer.fromJson(Map<String, dynamic> json) => PracticeAnswer(
        id: json['id'] as String,
        attemptId: json['attempt_id'] as String,
        questionId: json['question_id'] as String,
        selectedOptionLabel: json['selected_option_label'] as String?,
        isCorrect: json['is_correct'] as bool? ?? false,
        isSkipped: json['is_skipped'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'attempt_id': attemptId,
        'question_id': questionId,
        'selected_option_label': selectedOptionLabel,
        'is_correct': isCorrect,
        'is_skipped': isSkipped,
      };
}

class PracticeAttempt {
  final String id;
  final String userId;
  final String phaseId;
  final String subjectId;
  final int totalQuestions;
  final int correctCount;
  final int incorrectCount;
  final int skippedCount;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<PracticeAnswer> answers;

  const PracticeAttempt({
    required this.id,
    required this.userId,
    required this.phaseId,
    required this.subjectId,
    required this.totalQuestions,
    required this.correctCount,
    required this.incorrectCount,
    required this.skippedCount,
    required this.startedAt,
    this.completedAt,
    this.answers = const [],
  });

  double get percentage =>
      totalQuestions == 0 ? 0 : (correctCount / totalQuestions) * 100;

  factory PracticeAttempt.fromJson(Map<String, dynamic> json) {
    final rawAnswers = json['practice_answers'] as List<dynamic>? ?? const [];
    return PracticeAttempt(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      phaseId: json['phase_id'] as String,
      subjectId: json['subject_id'] as String,
      totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
      correctCount: (json['correct_count'] as num?)?.toInt() ?? 0,
      incorrectCount: (json['incorrect_count'] as num?)?.toInt() ?? 0,
      skippedCount: (json['skipped_count'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      answers: rawAnswers
          .map((a) => PracticeAnswer.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'phase_id': phaseId,
        'subject_id': subjectId,
        'total_questions': totalQuestions,
        'correct_count': correctCount,
        'incorrect_count': incorrectCount,
        'skipped_count': skippedCount,
        'started_at': startedAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };
}
