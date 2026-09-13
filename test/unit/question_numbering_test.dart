import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/validation/question_numbering.dart';

void main() {
  group('QuestionNumberingValidator.check', () {
    test('1. sequential questions pass with no issues', () {
      final report = QuestionNumberingValidator.check([1, 2, 3, 4, 5]);
      expect(report.isValid, isTrue);
      expect(report.hasErrors, isFalse);
    });

    test('2. duplicate numbers are detected as an error', () {
      final report = QuestionNumberingValidator.check([1, 2, 2, 4, 5]);
      expect(report.hasErrors, isTrue);
      expect(report.errors.single.message, 'Duplicate question number: 2');
    });

    test('3. a missing number is detected', () {
      final report = QuestionNumberingValidator.check([1, 2, 4, 5]);
      expect(report.isValid, isFalse);
      expect(report.warnings.any((w) => w.message == 'Missing question number: 3'), isTrue);
    });

    test('4. a gap is a warning, not a critical error, so it never blocks anything on its own',
        () {
      final report = QuestionNumberingValidator.check([1, 2, 4, 5]);
      expect(report.hasErrors, isFalse);
      expect(report.warnings, isNotEmpty);
    });

    test('duplicate + gap together produce both an error and a warning', () {
      // The exact combined example from the spec: 1, 2, 2, 4, 5.
      final report = QuestionNumberingValidator.check([1, 2, 2, 4, 5]);
      expect(report.errors.single.message, 'Duplicate question number: 2');
      expect(report.warnings.single.message, 'Missing question number: 3');
    });

    test('an empty list has no issues (nothing to validate)', () {
      final report = QuestionNumberingValidator.check([]);
      expect(report.isValid, isTrue);
    });

    test('a single question is always valid', () {
      final report = QuestionNumberingValidator.check([1]);
      expect(report.isValid, isTrue);
    });

    test('numbers out of input order are still checked correctly', () {
      final report = QuestionNumberingValidator.check([5, 3, 1, 4, 2]);
      expect(report.isValid, isTrue);
    });

    test('multiple duplicates and multiple gaps are all reported', () {
      final report = QuestionNumberingValidator.check([1, 1, 4, 4, 7]);
      expect(report.errors.map((e) => e.message),
          containsAll(['Duplicate question number: 1', 'Duplicate question number: 4']));
      expect(
        report.warnings.map((w) => w.message),
        containsAll([
          'Missing question number: 2',
          'Missing question number: 3',
          'Missing question number: 5',
          'Missing question number: 6',
        ]),
      );
    });
  });
}
