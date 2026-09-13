import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/constants/app_constants.dart';
import 'package:induction_program_past_papers/data/models/question.dart';
import 'package:induction_program_past_papers/data/models/question_option.dart';
import 'package:induction_program_past_papers/features/practice/practice_result.dart';

Question _mcq(String id, {required String correctLabel}) {
  return Question(
    id: id,
    paperSectionId: 'section-1',
    questionNumber: 1,
    questionType: QuestionType.mcq,
    questionText: 'Sample question',
    verificationStatus: 'VERIFIED',
    qualityStatus: QualityStatus.verified,
    displayOrder: 0,
    options: [
      QuestionOption(
        id: '$id-a',
        questionId: id,
        optionLabel: 'A',
        optionText: 'Option A',
        isVerifiedCorrect: correctLabel == 'A',
        displayOrder: 0,
      ),
      QuestionOption(
        id: '$id-b',
        questionId: id,
        optionLabel: 'B',
        optionText: 'Option B',
        isVerifiedCorrect: correctLabel == 'B',
        displayOrder: 1,
      ),
    ],
  );
}

void main() {
  group('PracticeQuestionResult', () {
    test('is correct when selected option matches the verified correct option', () {
      final result = PracticeQuestionResult(
        question: _mcq('q1', correctLabel: 'B'),
        selectedOptionLabel: 'B',
        isSkipped: false,
      );
      expect(result.isCorrect, isTrue);
    });

    test('is incorrect when selected option does not match', () {
      final result = PracticeQuestionResult(
        question: _mcq('q1', correctLabel: 'B'),
        selectedOptionLabel: 'A',
        isSkipped: false,
      );
      expect(result.isCorrect, isFalse);
    });

    test('is never correct when skipped, even if selectedOptionLabel is set', () {
      final result = PracticeQuestionResult(
        question: _mcq('q1', correctLabel: 'A'),
        selectedOptionLabel: 'A',
        isSkipped: true,
      );
      expect(result.isCorrect, isFalse);
    });
  });

  group('PracticeResult scoring', () {
    test('computes correct/incorrect/skipped counts and percentage', () {
      final result = PracticeResult(
        phaseId: 'phase-1',
        subjectId: 'subject-1',
        results: [
          PracticeQuestionResult(
              question: _mcq('q1', correctLabel: 'A'),
              selectedOptionLabel: 'A',
              isSkipped: false),
          PracticeQuestionResult(
              question: _mcq('q2', correctLabel: 'A'),
              selectedOptionLabel: 'B',
              isSkipped: false),
          PracticeQuestionResult(
              question: _mcq('q3', correctLabel: 'A'),
              selectedOptionLabel: null,
              isSkipped: true),
          PracticeQuestionResult(
              question: _mcq('q4', correctLabel: 'A'),
              selectedOptionLabel: 'A',
              isSkipped: false),
        ],
      );

      expect(result.total, 4);
      expect(result.correct, 2);
      expect(result.incorrect, 1);
      expect(result.skipped, 1);
      expect(result.percentage, 50.0);
    });

    test('percentage is 0 for an empty result set (no division by zero)', () {
      const result = PracticeResult(phaseId: 'p', subjectId: 's', results: []);
      expect(result.percentage, 0);
    });
  });
}
