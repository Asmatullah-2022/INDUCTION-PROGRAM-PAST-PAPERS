/// How an AI Teacher assistant message's content should be labeled —
/// mirrors the `ai_messages.content_kind` check constraint in
/// `007_ai_teacher.sql`. Never invent a value beyond what the backend
/// returned; a null/unrecognized kind renders as [general].
enum AiContentKind {
  /// The app's own verified data — not AI-authored text at all. Reserved
  /// for a future case where a response is composed entirely of verified
  /// fields; the current Edge Function always labels model output as one
  /// of the two AI-generated kinds below.
  verifiedAnswer,

  /// AI-authored text explaining verified content the backend supplied
  /// (a real question/answer from a PUBLISHED paper).
  aiGeneratedExplanationBasedOnVerified,

  /// AI-authored text with no verified content behind it — general
  /// educational help, not tied to any specific verified question.
  aiGeneratedAnswer,

  /// General educational chat with no question context at all.
  general,
}

extension AiContentKindX on AiContentKind {
  static AiContentKind fromString(String? value) {
    switch (value) {
      case 'VERIFIED_ANSWER':
        return AiContentKind.verifiedAnswer;
      case 'AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED':
        return AiContentKind.aiGeneratedExplanationBasedOnVerified;
      case 'AI_GENERATED_ANSWER':
        return AiContentKind.aiGeneratedAnswer;
      default:
        return AiContentKind.general;
    }
  }

  /// Exact label text required by the product spec — never paraphrase
  /// these, they're what tells a user whether they're reading the paper's
  /// own verified answer or the AI's own words.
  String get label {
    switch (this) {
      case AiContentKind.verifiedAnswer:
        return 'VERIFIED ANSWER';
      case AiContentKind.aiGeneratedExplanationBasedOnVerified:
        return 'AI-GENERATED EXPLANATION BASED ON VERIFIED CONTENT';
      case AiContentKind.aiGeneratedAnswer:
        return 'AI-GENERATED ANSWER';
      case AiContentKind.general:
        return 'AI-GENERATED';
    }
  }

  bool get isBasedOnVerifiedContent => this == AiContentKind.aiGeneratedExplanationBasedOnVerified;
}

enum AiMessageRole { user, assistant }

extension AiMessageRoleX on AiMessageRole {
  static AiMessageRole fromString(String value) => value == 'user' ? AiMessageRole.user : AiMessageRole.assistant;

  String get dbValue => this == AiMessageRole.user ? 'user' : 'assistant';
}

class AiMessage {
  final String id;
  final String conversationId;
  final AiMessageRole role;
  final String content;
  final AiContentKind? contentKind;
  final String? action;
  final DateTime createdAt;

  const AiMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.contentKind,
    this.action,
    required this.createdAt,
  });

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        role: AiMessageRoleX.fromString(json['role'] as String),
        content: json['content'] as String,
        contentKind: json['content_kind'] != null
            ? AiContentKindX.fromString(json['content_kind'] as String?)
            : null,
        action: json['action'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
