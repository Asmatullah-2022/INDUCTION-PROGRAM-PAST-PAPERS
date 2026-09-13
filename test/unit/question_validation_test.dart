import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/constants/app_constants.dart';
import 'package:induction_program_past_papers/core/errors/app_exception.dart';
import 'package:induction_program_past_papers/core/validation/question_validation.dart';

void main() {
  group('QuestionValidation.validate — quality note requirement', () {
    test('VERIFIED questions do not require a quality note', () {
      expect(
        () => QuestionValidation.validate(
          questionType: QuestionType.short,
          qualityStatus: QualityStatus.verified,
          qualityNote: null,
        ),
        returnsNormally,
      );
    });

    test('QUESTIONABLE without a note throws', () {
      expect(
        () => QuestionValidation.validate(
          questionType: QuestionType.short,
          qualityStatus: QualityStatus.questionable,
          qualityNote: '   ',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('QUESTIONABLE with a note passes', () {
      expect(
        () => QuestionValidation.validate(
          questionType: QuestionType.short,
          qualityStatus: QualityStatus.questionable,
          qualityNote: 'Wording is ambiguous because...',
        ),
        returnsNormally,
      );
    });
  });

  group('QuestionValidation.validate — MCQ option rules', () {
    test('fewer than 2 options throws', () {
      expect(
        () => QuestionValidation.validate(
          questionType: QuestionType.mcq,
          qualityStatus: QualityStatus.verified,
          options: const [(label: 'A', text: 'Only one', isCorrect: true)],
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('no option marked correct throws', () {
      expect(
        () => QuestionValidation.validate(
          questionType: QuestionType.mcq,
          qualityStatus: QualityStatus.verified,
          options: const [
            (label: 'A', text: 'x', isCorrect: false),
            (label: 'B', text: 'y', isCorrect: false),
          ],
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('more than one option marked correct throws', () {
      expect(
        () => QuestionValidation.validate(
          questionType: QuestionType.mcq,
          qualityStatus: QualityStatus.verified,
          options: const [
            (label: 'A', text: 'x', isCorrect: true),
            (label: 'B', text: 'y', isCorrect: true),
          ],
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('duplicate option labels throw', () {
      expect(
        () => QuestionValidation.validate(
          questionType: QuestionType.mcq,
          qualityStatus: QualityStatus.verified,
          options: const [
            (label: 'A', text: 'x', isCorrect: true),
            (label: 'A', text: 'y', isCorrect: false),
          ],
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('exactly one correct option among 2+ passes', () {
      expect(
        () => QuestionValidation.validate(
          questionType: QuestionType.mcq,
          qualityStatus: QualityStatus.verified,
          options: const [
            (label: 'A', text: 'x', isCorrect: false),
            (label: 'B', text: 'y', isCorrect: true),
            (label: 'C', text: 'z', isCorrect: false),
          ],
        ),
        returnsNormally,
      );
    });

    test('short/long questions are not subject to MCQ option rules', () {
      expect(
        () => QuestionValidation.validate(
          questionType: QuestionType.long,
          qualityStatus: QualityStatus.verified,
          options: const [],
        ),
        returnsNormally,
      );
    });
  });

  group('QuestionValidation.resolveVerificationStatus', () {
    test('no original marked option means VERIFIED regardless of correct label', () {
      expect(
        QuestionValidation.resolveVerificationStatus(
          originalMarkedOption: null,
          verifiedCorrectLabel: 'C',
        ),
        'VERIFIED',
      );
      expect(
        QuestionValidation.resolveVerificationStatus(
          originalMarkedOption: '',
          verifiedCorrectLabel: 'C',
        ),
        'VERIFIED',
      );
    });

    test('original marked option matching the verified answer is VERIFIED', () {
      expect(
        QuestionValidation.resolveVerificationStatus(
          originalMarkedOption: 'B',
          verifiedCorrectLabel: 'B',
        ),
        'VERIFIED',
      );
    });

    test('original marked option differing from the verified answer is PAPER_ANSWER_ERROR', () {
      // This is the exact scenario from spec section 5: the supplied paper
      // ticked B, but independent verification found C correct.
      expect(
        QuestionValidation.resolveVerificationStatus(
          originalMarkedOption: 'B',
          verifiedCorrectLabel: 'C',
        ),
        'PAPER_ANSWER_ERROR',
      );
    });
  });
}
