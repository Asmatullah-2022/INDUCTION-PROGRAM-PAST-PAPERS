import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/errors/app_exception.dart';
import 'package:induction_program_past_papers/core/validation/ai_teacher_validation.dart';
import 'package:induction_program_past_papers/data/models/ai_message.dart';

void main() {
  group('AiContentKindX.label — verified vs AI-generated labelling', () {
    test('aiGeneratedExplanationBasedOnVerified is labelled distinctly from a raw verified answer', () {
      expect(
        AiContentKindX.fromString('AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED').label,
        'AI-GENERATED EXPLANATION BASED ON VERIFIED CONTENT',
      );
    });

    test('aiGeneratedAnswer is never labelled as if it were verified', () {
      final label = AiContentKindX.fromString('AI_GENERATED_ANSWER').label;
      expect(label, 'AI-GENERATED ANSWER');
      expect(label.contains('VERIFIED'), isFalse);
    });

    test('verifiedAnswer keeps its own distinct label', () {
      expect(AiContentKindX.fromString('VERIFIED_ANSWER').label, 'VERIFIED ANSWER');
    });

    test('an unrecognized/null content_kind falls back to general, never to verified', () {
      final kind = AiContentKindX.fromString(null);
      expect(kind, AiContentKind.general);
      expect(kind.label, isNot(contains('VERIFIED ANSWER')));
    });

    test('only the verified-based-explanation kind reports isBasedOnVerifiedContent', () {
      expect(AiContentKind.aiGeneratedExplanationBasedOnVerified.isBasedOnVerifiedContent, isTrue);
      expect(AiContentKind.aiGeneratedAnswer.isBasedOnVerifiedContent, isFalse);
      expect(AiContentKind.general.isBasedOnVerifiedContent, isFalse);
      expect(AiContentKind.verifiedAnswer.isBasedOnVerifiedContent, isFalse);
    });
  });

  group('AiPromptValidator.validate — maximum prompt validation', () {
    test('a normal-length message passes', () {
      expect(() => AiPromptValidator.validate('Explain formative assessment.'), returnsNormally);
    });

    test('an empty message is rejected', () {
      expect(() => AiPromptValidator.validate(''), throwsA(isA<AppException>()));
      expect(() => AiPromptValidator.validate('   '), throwsA(isA<AppException>()));
    });

    test('a message exceeding the max length is rejected', () {
      final tooLong = 'a' * 100;
      expect(
        () => AiPromptValidator.validate(tooLong, maxChars: 50),
        throwsA(isA<AppException>()),
      );
    });

    test('a message exactly at the max length passes', () {
      final exact = 'a' * 50;
      expect(() => AiPromptValidator.validate(exact, maxChars: 50), returnsNormally);
    });
  });

  group('AiTeacherErrorMapper — provider failure / rate-limit handling', () {
    test('rate_limited maps to a validation-type exception with a clear message', () {
      final e = AiTeacherErrorMapper.mapErrorCode('rate_limited', null);
      expect(e.type, AppErrorType.validation);
      expect(e.message, contains('limit'));
    });

    test('provider_unavailable maps to a server-type exception, never leaking internals', () {
      final e = AiTeacherErrorMapper.mapErrorCode('provider_unavailable', null);
      expect(e.type, AppErrorType.server);
      expect(e.message, isNot(contains('api_key')));
      expect(e.message, isNot(contains('Anthropic')));
    });

    test('unauthorized maps to a session-expired exception', () {
      final e = AiTeacherErrorMapper.mapErrorCode('unauthorized', null);
      expect(e.type, AppErrorType.sessionExpired);
    });

    test('an unrecognized code still returns a safe, generic exception', () {
      final e = AiTeacherErrorMapper.mapErrorCode('something_new', null);
      expect(e.message, isNotEmpty);
    });

    test('a backend-supplied message is preferred over the generic fallback', () {
      final e = AiTeacherErrorMapper.mapErrorCode('rate_limited', 'Custom limit message.');
      expect(e.message, 'Custom limit message.');
    });

    test('mapHttpStatus(429) is treated as rate limiting', () {
      final e = AiTeacherErrorMapper.mapHttpStatus(429);
      expect(e.type, AppErrorType.validation);
    });

    test('mapHttpStatus for any other status falls back to a generic server error', () {
      final e = AiTeacherErrorMapper.mapHttpStatus(500);
      expect(e.type, AppErrorType.server);
    });
  });

  group('AiContentKind — practice content and the NEEDS REVIEW badge', () {
    test('AI_GENERATED_PRACTICE gets its own distinct label, never confused with a real answer', () {
      final kind = AiContentKindX.fromString('AI_GENERATED_PRACTICE');
      expect(kind, AiContentKind.aiGeneratedPractice);
      expect(kind.label, 'AI-GENERATED PRACTICE');
      expect(kind.label.contains('ANSWER'), isFalse);
    });

    test('needsReviewBadge is true for ungrounded AI content (answer, practice)', () {
      expect(AiContentKind.aiGeneratedAnswer.needsReviewBadge, isTrue);
      expect(AiContentKind.aiGeneratedPractice.needsReviewBadge, isTrue);
    });

    test('needsReviewBadge is false for verified-grounded or raw verified content', () {
      expect(AiContentKind.aiGeneratedExplanationBasedOnVerified.needsReviewBadge, isFalse);
      expect(AiContentKind.verifiedAnswer.needsReviewBadge, isFalse);
    });
  });

  group('AiDiscrepancyDetector — verified content must have priority', () {
    test('flags a mismatch between the AI\'s stated answer and the verified answer', () {
      expect(
        AiDiscrepancyDetector.hasDiscrepancy('Correct Answer is C.\nBecause...', 'B'),
        isTrue,
      );
    });

    test('does not flag when the AI\'s stated answer matches the verified answer', () {
      expect(
        AiDiscrepancyDetector.hasDiscrepancy('Correct Answer is B.\nBecause...', 'B'),
        isFalse,
      );
    });

    test('comparison is case-insensitive', () {
      expect(
        AiDiscrepancyDetector.hasDiscrepancy('correct answer is b.\nBecause...', 'B'),
        isFalse,
      );
    });

    test('never flags a discrepancy when no clear statement is found', () {
      expect(
        AiDiscrepancyDetector.hasDiscrepancy('This concept relates to formative assessment.', 'B'),
        isFalse,
      );
    });
  });

  group('AiTeacherActionX — quick action sets never overlap incorrectly', () {
    test('every action has a non-empty label and dbValue', () {
      for (final action in AiTeacherAction.values) {
        expect(action.label, isNotEmpty);
        expect(action.dbValue, isNotEmpty);
      }
    });

    test('dbValue values are all unique (no backend ambiguity)', () {
      final values = AiTeacherAction.values.map((a) => a.dbValue).toSet();
      expect(values.length, AiTeacherAction.values.length);
    });

    test('question-context actions include explaining the MCQ', () {
      expect(AiTeacherActionX.questionContextActions, contains(AiTeacherAction.explainMcq));
    });

    test('general actions include study planning, which needs no question context', () {
      expect(AiTeacherActionX.generalActions, contains(AiTeacherAction.studyPlan));
    });
  });
}
