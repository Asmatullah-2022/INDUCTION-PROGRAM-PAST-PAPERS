class AiConversation {
  final String id;
  final String userId;
  final String title;
  final String? phaseId;
  final String? subjectId;
  final String? paperId;
  final String? questionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AiConversation({
    required this.id,
    required this.userId,
    required this.title,
    this.phaseId,
    this.subjectId,
    this.paperId,
    this.questionId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiConversation.fromJson(Map<String, dynamic> json) => AiConversation(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String? ?? 'New Conversation',
        phaseId: json['phase_id'] as String?,
        subjectId: json['subject_id'] as String?,
        paperId: json['paper_id'] as String?,
        questionId: json['question_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
