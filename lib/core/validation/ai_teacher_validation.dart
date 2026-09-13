import '../errors/app_exception.dart';

/// The fixed action vocabulary the `ai-teacher` Edge Function accepts
/// (see its `ALLOWED_ACTIONS` set) — kept as an enum here so the Flutter
/// app can only ever send a value the backend recognizes; there is no
/// free-text "action" field anywhere in the UI.
enum AiTeacherAction {
  ask,
  explainQuestion,
  explainMcq,
  explainSimply,
  explainUrdu,
  giveExample,
  makeQuiz,
  similarQuestions,
  examTip,
  summarize,
  revisionNotes,
  studyPlan,
}

extension AiTeacherActionX on AiTeacherAction {
  String get dbValue {
    switch (this) {
      case AiTeacherAction.ask:
        return 'ask';
      case AiTeacherAction.explainQuestion:
        return 'explain_question';
      case AiTeacherAction.explainMcq:
        return 'explain_mcq';
      case AiTeacherAction.explainSimply:
        return 'explain_simply';
      case AiTeacherAction.explainUrdu:
        return 'explain_urdu';
      case AiTeacherAction.giveExample:
        return 'give_example';
      case AiTeacherAction.makeQuiz:
        return 'make_quiz';
      case AiTeacherAction.similarQuestions:
        return 'similar_questions';
      case AiTeacherAction.examTip:
        return 'exam_tip';
      case AiTeacherAction.summarize:
        return 'summarize';
      case AiTeacherAction.revisionNotes:
        return 'revision_notes';
      case AiTeacherAction.studyPlan:
        return 'study_plan';
    }
  }

  /// Button label for the quick-actions row.
  String get label {
    switch (this) {
      case AiTeacherAction.ask:
        return 'Ask';
      case AiTeacherAction.explainQuestion:
        return 'Explain This Question';
      case AiTeacherAction.explainMcq:
        return 'Explain This MCQ';
      case AiTeacherAction.explainSimply:
        return 'Explain Simply';
      case AiTeacherAction.explainUrdu:
        return 'Urdu Explanation';
      case AiTeacherAction.giveExample:
        return 'Give Example';
      case AiTeacherAction.makeQuiz:
        return 'Make Quiz';
      case AiTeacherAction.similarQuestions:
        return 'Similar Questions';
      case AiTeacherAction.examTip:
        return 'Exam Tip';
      case AiTeacherAction.summarize:
        return 'Summarize';
      case AiTeacherAction.revisionNotes:
        return 'Revision Notes';
      case AiTeacherAction.studyPlan:
        return 'Study Plan';
    }
  }

  /// Quick actions shown when the chat was opened from a specific
  /// question — "Why B?" style follow-ups make sense here.
  static const List<AiTeacherAction> questionContextActions = [
    AiTeacherAction.explainSimply,
    AiTeacherAction.explainMcq,
    AiTeacherAction.giveExample,
    AiTeacherAction.explainUrdu,
    AiTeacherAction.examTip,
    AiTeacherAction.similarQuestions,
  ];

  /// Quick actions shown for a general, no-question-context conversation.
  static const List<AiTeacherAction> generalActions = [
    AiTeacherAction.explainSimply,
    AiTeacherAction.explainUrdu,
    AiTeacherAction.giveExample,
    AiTeacherAction.makeQuiz,
    AiTeacherAction.examTip,
    AiTeacherAction.summarize,
    AiTeacherAction.revisionNotes,
    AiTeacherAction.studyPlan,
  ];
}

/// Maps the `ai-teacher` Edge Function's error codes to a user-facing
/// [AppException] — the one place this mapping happens, shared by
/// AiTeacherRepository's two error paths (a structured `{error, message}`
/// body, or a raw [FunctionException]-shaped failure) and directly
/// unit-tested without needing a live Supabase project.
class AiTeacherErrorMapper {
  AiTeacherErrorMapper._();

  static AppException mapErrorCode(String code, String? message) {
    switch (code) {
      case 'rate_limited':
        return AppException(
          message ?? "You've reached today's AI Teacher request limit. Please try again tomorrow.",
          type: AppErrorType.validation,
        );
      case 'provider_unavailable':
        return AppException(
          message ?? 'AI Teacher is temporarily unavailable. Please try again.',
          type: AppErrorType.server,
        );
      case 'unauthorized':
        return AppException.sessionExpired();
      case 'invalid_request':
        return AppException(message ?? 'That request could not be processed.');
      default:
        return AppException(message ?? 'Something went wrong. Please try again.');
    }
  }

  /// For a raw HTTP-status-only failure (no structured error body) —
  /// e.g. a 429 from an infrastructure layer in front of the function.
  static AppException mapHttpStatus(int status) {
    if (status == 429) {
      return const AppException(
        "You've reached today's AI Teacher request limit. Please try again tomorrow.",
        type: AppErrorType.validation,
      );
    }
    return AppException.server();
  }
}

/// Detects a stated MCQ option letter in an AI explanation that
/// contradicts the app's own verified answer — the client-side half of
/// the "verified content has priority" rule (see CLAUDE.md "AI Teacher
/// Rules"). This is a UX safety net over text the backend already
/// returned, not a security control: the Edge Function never lets the AI
/// overwrite a verified answer in the database, this only flags the
/// (hopefully rare) case where the model's own wording disagrees with it
/// so the user is warned rather than silently misled. Relies on the
/// system prompt's `Correct Answer is LETTER.` convention (rule 12 in
/// supabase/functions/ai-teacher/index.ts) — if the AI doesn't follow
/// that convention, this simply finds nothing and never flags a false
/// discrepancy.
class AiDiscrepancyDetector {
  AiDiscrepancyDetector._();

  static final RegExp _statedAnswerPattern = RegExp(
    r'correct\s+answer\s+is[:\s]+\(?([A-Da-d])\)?',
    caseSensitive: false,
  );

  /// Returns true only when the AI text explicitly states an option
  /// letter that differs from [verifiedAnswer]. Never flags when no clear
  /// statement is found.
  static bool hasDiscrepancy(String aiText, String verifiedAnswer) {
    final match = _statedAnswerPattern.firstMatch(aiText);
    final stated = match?.group(1);
    if (stated == null) return false;
    return stated.toUpperCase() != verifiedAnswer.trim().toUpperCase();
  }
}

/// Pure request validation mirroring the Edge Function's own checks
/// (message required, max length) — see 007_ai_teacher.sql /
/// supabase/functions/ai-teacher/index.ts. Client-side validation here is
/// a UX convenience that fails fast; the Edge Function re-validates
/// independently and is the actual gate, same pattern as
/// PaperQualityChecker / admin_transition_paper_status.
class AiPromptValidator {
  AiPromptValidator._();

  static const int defaultMaxChars = 4000;

  /// Throws an [AppException] if [message] is empty or exceeds
  /// [maxChars]; returns normally otherwise.
  static void validate(String message, {int maxChars = defaultMaxChars}) {
    if (message.trim().isEmpty) {
      throw const AppException('Please enter a message.');
    }
    if (message.length > maxChars) {
      throw AppException(
        'Your message is too long (${message.length} characters). '
        'Please shorten it to $maxChars characters or fewer.',
      );
    }
  }
}
