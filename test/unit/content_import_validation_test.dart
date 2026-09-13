import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/validation/content_import_validation.dart';

Map<String, dynamic> _validMcqQuestion(int number) => {
      'question_number': number,
      'question_type': 'mcq',
      'question_text': 'What is 2 + 2?',
      'quality_status': 'VERIFIED',
      'options': [
        {'option_label': 'A', 'option_text': '3', 'is_verified_correct': false},
        {'option_label': 'B', 'option_text': '4', 'is_verified_correct': true},
      ],
    };

Map<String, dynamic> _validPaper({List<Map<String, dynamic>>? sections}) => {
      'phase_slug': 'phase-4',
      'subject_slug': 'english',
      'title': 'Test Paper',
      'sections': sections ??
          [
            {
              'section_name': 'Section A',
              'section_code': 'A',
              'questions': [_validMcqQuestion(1), _validMcqQuestion(2)],
            },
          ],
    };

void main() {
  group('ContentImportValidator.validate — paper-level rules', () {
    test('a fully valid paper has no issues', () {
      final report = ContentImportValidator.validate(_validPaper());
      expect(report.hasCriticalErrors, isFalse);
      expect(report.issues, isEmpty);
    });

    test('an invalid phase_slug is a critical error', () {
      final paper = _validPaper()..['phase_slug'] = 'phase-99';
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('phase_slug')), isTrue);
    });

    test('an invalid subject_slug is a critical error', () {
      final paper = _validPaper()..['subject_slug'] = 'not-a-real-subject';
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('subject_slug')), isTrue);
    });

    test('a year field is a critical error, matching the no-year rule', () {
      final paper = _validPaper()..['year'] = 2024;
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('year-based field')), isTrue);
    });

    test('a missing title is a critical error', () {
      final paper = _validPaper()..remove('title');
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isTrue);
    });

    test('no sections at all is a critical error', () {
      final paper = _validPaper()..['sections'] = <Map<String, dynamic>>[];
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isTrue);
    });

    test('an empty section is a warning, not a critical error', () {
      final paper = _validPaper(sections: [
        {'section_name': 'Section B', 'section_code': 'B', 'questions': <Map<String, dynamic>>[]},
      ]);
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isFalse);
      expect(report.warnings, isNotEmpty);
    });
  });

  group('ContentImportValidator.validate — question-level rules', () {
    test('an MCQ with no correct option is a critical error', () {
      final badQuestion = _validMcqQuestion(1);
      (badQuestion['options'] as List).cast<Map<String, dynamic>>().forEach((o) {
        o['is_verified_correct'] = false;
      });
      final paper = _validPaper(sections: [
        {'section_name': 'Section A', 'section_code': 'A', 'questions': [badQuestion]},
      ]);
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isTrue);
    });

    test('a duplicate question number within a section is a critical error', () {
      final paper = _validPaper(sections: [
        {
          'section_name': 'Section A',
          'section_code': 'A',
          'questions': [_validMcqQuestion(1), _validMcqQuestion(1)],
        },
      ]);
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('Duplicate question number')), isTrue);
    });

    test('a numbering gap is a warning, not a critical error', () {
      final paper = _validPaper(sections: [
        {
          'section_name': 'Section A',
          'section_code': 'A',
          'questions': [_validMcqQuestion(1), _validMcqQuestion(3)],
        },
      ]);
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isFalse);
      expect(report.warnings.any((w) => w.message.contains('Missing question number')), isTrue);
    });

    test('a non-VERIFIED quality_status without a quality_note is a critical error', () {
      final question = _validMcqQuestion(1)..['quality_status'] = 'QUESTIONABLE';
      final paper = _validPaper(sections: [
        {'section_name': 'Section A', 'section_code': 'A', 'questions': [question]},
      ]);
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('quality_note')), isTrue);
    });

    test('a non-VERIFIED quality_status with a quality_note passes', () {
      final question = _validMcqQuestion(1)
        ..['quality_status'] = 'QUESTIONABLE'
        ..['quality_note'] = 'Wording is ambiguous.';
      final paper = _validPaper(sections: [
        {'section_name': 'Section A', 'section_code': 'A', 'questions': [question]},
      ]);
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isFalse);
    });

    test('a short question missing verified_answer is a critical error', () {
      final question = {
        'question_number': 1,
        'question_type': 'short',
        'question_text': 'Define photosynthesis.',
        'quality_status': 'VERIFIED',
      };
      final paper = _validPaper(sections: [
        {'section_name': 'Section B', 'section_code': 'B', 'questions': [question]},
      ]);
      final report = ContentImportValidator.validate(paper);
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('verified_answer')), isTrue);
    });
  });
}
