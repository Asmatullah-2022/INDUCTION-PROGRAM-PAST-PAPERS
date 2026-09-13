import '../../core/constants/app_constants.dart';
import 'question_option.dart';

/// A single question within a paper section (MCQ, short, or long).
///
/// [originalMarkedOption] is what was ticked/marked in the *supplied*
/// paper; [verifiedAnswer] is the academically correct answer after
/// independent checking. These are deliberately separate — a tick on the
/// original paper is never auto-accepted as correct.
class Question {
  final String id;
  final String paperSectionId;
  final int questionNumber;
  final QuestionType questionType;
  final String questionText;
  final int? marks;
  final String? originalMarkedOption;
  final String? verifiedAnswer;
  final String verificationStatus; // e.g. VERIFIED, PAPER_ANSWER_ERROR
  final String? explanation;
  final QualityStatus qualityStatus;
  final String? qualityNote;
  final int displayOrder;
  final List<QuestionOption> options;

  const Question({
    required this.id,
    required this.paperSectionId,
    required this.questionNumber,
    required this.questionType,
    required this.questionText,
    this.marks,
    this.originalMarkedOption,
    this.verifiedAnswer,
    required this.verificationStatus,
    this.explanation,
    required this.qualityStatus,
    this.qualityNote,
    required this.displayOrder,
    this.options = const [],
  });

  bool get hasAnswerKeyDiscrepancy => verificationStatus == 'PAPER_ANSWER_ERROR';

  factory Question.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['question_options'] as List<dynamic>? ?? const [];
    return Question(
      id: json['id'] as String,
      paperSectionId: json['paper_section_id'] as String,
      questionNumber: (json['question_number'] as num).toInt(),
      questionType: QuestionTypeX.fromString(json['question_type'] as String?),
      questionText: json['question_text'] as String,
      marks: (json['marks'] as num?)?.toInt(),
      originalMarkedOption: json['original_marked_option'] as String?,
      verifiedAnswer: json['verified_answer'] as String?,
      verificationStatus: json['verification_status'] as String? ?? 'VERIFIED',
      explanation: json['explanation'] as String?,
      qualityStatus: QualityStatusX.fromString(json['quality_status'] as String?),
      qualityNote: json['quality_note'] as String?,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      options: rawOptions
          .map((o) => QuestionOption.fromJson(o as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'paper_section_id': paperSectionId,
        'question_number': questionNumber,
        'question_type': questionType.dbValue,
        'question_text': questionText,
        'marks': marks,
        'original_marked_option': originalMarkedOption,
        'verified_answer': verifiedAnswer,
        'verification_status': verificationStatus,
        'explanation': explanation,
        'quality_status': qualityStatus.dbValue,
        'quality_note': qualityNote,
        'display_order': displayOrder,
        'question_options': options.map((o) => o.toJson()).toList(),
      };
}
