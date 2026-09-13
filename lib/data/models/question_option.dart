class QuestionOption {
  final String id;
  final String questionId;
  final String optionLabel;
  final String optionText;
  final bool isVerifiedCorrect;
  final int displayOrder;

  const QuestionOption({
    required this.id,
    required this.questionId,
    required this.optionLabel,
    required this.optionText,
    required this.isVerifiedCorrect,
    required this.displayOrder,
  });

  factory QuestionOption.fromJson(Map<String, dynamic> json) => QuestionOption(
        id: json['id'] as String,
        questionId: json['question_id'] as String,
        optionLabel: json['option_label'] as String,
        optionText: json['option_text'] as String,
        isVerifiedCorrect: json['is_verified_correct'] as bool? ?? false,
        displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'question_id': questionId,
        'option_label': optionLabel,
        'option_text': optionText,
        'is_verified_correct': isVerifiedCorrect,
        'display_order': displayOrder,
      };
}
