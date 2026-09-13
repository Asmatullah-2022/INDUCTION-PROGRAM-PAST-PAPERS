import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/constants/app_constants.dart';
import 'package:induction_program_past_papers/core/validation/paper_status.dart';
import 'package:induction_program_past_papers/data/models/paper.dart';
import 'package:induction_program_past_papers/data/models/paper_section.dart';
import 'package:induction_program_past_papers/data/models/question.dart';
import 'package:induction_program_past_papers/data/models/question_option.dart';

Paper _paper({
  String contentStatus = 'DRAFT',
  String? sourceFileUrl = 'https://example.test/original.pdf',
}) {
  final now = DateTime(2026, 1, 1);
  return Paper(
    id: 'paper-1',
    phaseId: 'phase-1',
    subjectId: 'subject-1',
    title: 'Test Paper',
    contentStatus: contentStatus,
    verificationStatus: contentStatus,
    sourceFileUrl: sourceFileUrl,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

PaperSection _section(String code, {int order = 0}) => PaperSection(
      id: 'section-$code',
      paperId: 'paper-1',
      sectionName: 'Section $code',
      sectionCode: code,
      displayOrder: order,
    );

Question _mcqQuestion({
  required String id,
  required int number,
  String text = 'What is 2 + 2?',
  List<QuestionOption> options = const [],
  QualityStatus qualityStatus = QualityStatus.verified,
}) =>
    Question(
      id: id,
      paperSectionId: 'section-A',
      questionNumber: number,
      questionType: QuestionType.mcq,
      questionText: text,
      verificationStatus: 'VERIFIED',
      qualityStatus: qualityStatus,
      displayOrder: number,
      options: options,
    );

Question _shortQuestion({
  required String id,
  required int number,
  String text = 'Define photosynthesis.',
  String? verifiedAnswer = 'The process by which plants convert light to energy.',
  QualityStatus qualityStatus = QualityStatus.verified,
  int? marks,
}) =>
    Question(
      id: id,
      paperSectionId: 'section-B',
      questionNumber: number,
      questionType: QuestionType.short,
      questionText: text,
      verifiedAnswer: verifiedAnswer,
      verificationStatus: 'VERIFIED',
      qualityStatus: qualityStatus,
      displayOrder: number,
      marks: marks,
    );

List<QuestionOption> _twoOptionsOneCorrect() => [
      const QuestionOption(
        id: 'o1',
        questionId: 'q1',
        optionLabel: 'A',
        optionText: '3',
        isVerifiedCorrect: false,
        displayOrder: 0,
      ),
      const QuestionOption(
        id: 'o2',
        questionId: 'q1',
        optionLabel: 'B',
        optionText: '4',
        isVerifiedCorrect: true,
        displayOrder: 1,
      ),
    ];

void main() {
  group('PaperStatusTransitions', () {
    test('DRAFT can move to UNDER_REVIEW or ARCHIVED only', () {
      expect(PaperStatusTransitions.isAllowed('DRAFT', 'UNDER_REVIEW'), isTrue);
      expect(PaperStatusTransitions.isAllowed('DRAFT', 'ARCHIVED'), isTrue);
      expect(PaperStatusTransitions.isAllowed('DRAFT', 'VERIFIED'), isFalse);
      expect(PaperStatusTransitions.isAllowed('DRAFT', 'PUBLISHED'), isFalse);
    });

    test('UNDER_REVIEW can move to DRAFT, VERIFIED, or ARCHIVED', () {
      expect(PaperStatusTransitions.isAllowed('UNDER_REVIEW', 'DRAFT'), isTrue);
      expect(PaperStatusTransitions.isAllowed('UNDER_REVIEW', 'VERIFIED'), isTrue);
      expect(PaperStatusTransitions.isAllowed('UNDER_REVIEW', 'ARCHIVED'), isTrue);
      expect(PaperStatusTransitions.isAllowed('UNDER_REVIEW', 'PUBLISHED'), isFalse);
    });

    test('VERIFIED can move to UNDER_REVIEW, PUBLISHED, or ARCHIVED — never DRAFT directly', () {
      expect(PaperStatusTransitions.isAllowed('VERIFIED', 'PUBLISHED'), isTrue);
      expect(PaperStatusTransitions.isAllowed('VERIFIED', 'UNDER_REVIEW'), isTrue);
      expect(PaperStatusTransitions.isAllowed('VERIFIED', 'ARCHIVED'), isTrue);
      expect(PaperStatusTransitions.isAllowed('VERIFIED', 'DRAFT'), isFalse);
    });

    test('PUBLISHED can only unpublish to VERIFIED or move to ARCHIVED', () {
      expect(PaperStatusTransitions.isAllowed('PUBLISHED', 'VERIFIED'), isTrue);
      expect(PaperStatusTransitions.isAllowed('PUBLISHED', 'ARCHIVED'), isTrue);
      expect(PaperStatusTransitions.isAllowed('PUBLISHED', 'DRAFT'), isFalse);
      expect(PaperStatusTransitions.isAllowed('PUBLISHED', 'UNDER_REVIEW'), isFalse);
    });

    test('ARCHIVED can only be restored to DRAFT', () {
      expect(PaperStatusTransitions.isAllowed('ARCHIVED', 'DRAFT'), isTrue);
      expect(PaperStatusTransitions.isAllowed('ARCHIVED', 'PUBLISHED'), isFalse);
    });

    test('a status "transitioning" to itself is always allowed (no-op)', () {
      for (final status in PaperStatus.all) {
        expect(PaperStatusTransitions.isAllowed(status, status), isTrue);
      }
    });

    test('allowedNextStatuses returns the exact allowed set for each status', () {
      expect(PaperStatusTransitions.allowedNextStatuses('DRAFT'),
          containsAll(['UNDER_REVIEW', 'ARCHIVED']));
      expect(PaperStatusTransitions.allowedNextStatuses('ARCHIVED'), ['DRAFT']);
    });
  });

  group('PaperQualityChecker — missing source blocks publication', () {
    test('a paper with no source file is a critical error', () {
      final report = PaperQualityChecker.check(
        paper: _paper(sourceFileUrl: null),
        sections: [
          (
            section: _section('A'),
            questions: [_mcqQuestion(id: 'q1', number: 1, options: _twoOptionsOneCorrect())],
          ),
        ],
      );
      expect(report.hasCriticalErrors, isTrue);
      expect(report.category, QualityCategory.error);
      expect(report.errors.any((e) => e.message.contains('MISSING SOURCE PAPER')), isTrue);
    });

    test('a paper with no sections at all is a critical error', () {
      final report = PaperQualityChecker.check(paper: _paper(), sections: const []);
      expect(report.hasCriticalErrors, isTrue);
    });

    test('a section with zero questions is a critical error', () {
      final report = PaperQualityChecker.check(
        paper: _paper(),
        sections: [(section: _section('A'), questions: const [])],
      );
      expect(report.hasCriticalErrors, isTrue);
    });
  });

  group('PaperQualityChecker — question-level rules', () {
    test('duplicate question numbers within a section are a critical error', () {
      final report = PaperQualityChecker.check(
        paper: _paper(),
        sections: [
          (
            section: _section('A'),
            questions: [
              _mcqQuestion(id: 'q1', number: 1, options: _twoOptionsOneCorrect()),
              _mcqQuestion(id: 'q2', number: 1, options: _twoOptionsOneCorrect()),
            ],
          ),
        ],
      );
      expect(report.hasCriticalErrors, isTrue);
      expect(
          report.errors.any((e) => e.message.toLowerCase().contains('duplicate question number')),
          isTrue);
    });

    test('an MCQ with no correct option is a critical error', () {
      final report = PaperQualityChecker.check(
        paper: _paper(),
        sections: [
          (
            section: _section('A'),
            questions: [
              _mcqQuestion(id: 'q1', number: 1, options: const [
                QuestionOption(
                  id: 'o1',
                  questionId: 'q1',
                  optionLabel: 'A',
                  optionText: '3',
                  isVerifiedCorrect: false,
                  displayOrder: 0,
                ),
                QuestionOption(
                  id: 'o2',
                  questionId: 'q1',
                  optionLabel: 'B',
                  optionText: '4',
                  isVerifiedCorrect: false,
                  displayOrder: 1,
                ),
              ]),
            ],
          ),
        ],
      );
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('exactly one correct option')), isTrue);
    });

    test('a short/long question missing a verified answer is a critical error', () {
      final report = PaperQualityChecker.check(
        paper: _paper(),
        sections: [
          (section: _section('B'), questions: [_shortQuestion(id: 'q1', number: 1, verifiedAnswer: '')]),
        ],
      );
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('missing a verified answer')), isTrue);
    });

    test('negative marks are a critical error', () {
      final report = PaperQualityChecker.check(
        paper: _paper(),
        sections: [
          (section: _section('B'), questions: [_shortQuestion(id: 'q1', number: 1, marks: -5)]),
        ],
      );
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('marks cannot be negative')), isTrue);
    });

    test('a non-VERIFIED quality_status is a warning, not a critical error', () {
      final report = PaperQualityChecker.check(
        paper: _paper(),
        sections: [
          (
            section: _section('A'),
            questions: [
              _mcqQuestion(
                id: 'q1',
                number: 1,
                options: _twoOptionsOneCorrect(),
                qualityStatus: QualityStatus.questionable,
              ),
            ],
          ),
        ],
      );
      expect(report.hasCriticalErrors, isFalse);
      expect(report.warnings, isNotEmpty);
      expect(report.category, QualityCategory.warning);
    });

    test('5. an empty question_text is a critical error', () {
      final report = PaperQualityChecker.check(
        paper: _paper(),
        sections: [
          (
            section: _section('A'),
            questions: [_mcqQuestion(id: 'q1', number: 1, text: '   ', options: _twoOptionsOneCorrect())],
          ),
        ],
      );
      expect(report.hasCriticalErrors, isTrue);
      expect(report.errors.any((e) => e.message.contains('question text is empty')), isTrue);
    });

    test('a fully clean paper passes with score 100 and PASS category', () {
      final report = PaperQualityChecker.check(
        paper: _paper(),
        sections: [
          (
            section: _section('A'),
            questions: [_mcqQuestion(id: 'q1', number: 1, options: _twoOptionsOneCorrect())],
          ),
          (
            section: _section('B'),
            questions: [_shortQuestion(id: 'q2', number: 1)],
          ),
        ],
      );
      expect(report.hasCriticalErrors, isFalse);
      expect(report.warnings, isEmpty);
      expect(report.score, 100);
      expect(report.category, QualityCategory.pass);
    });
  });

  group('PaperStatusPresentation', () {
    test('a DRAFT paper with no source file is labeled Missing Source', () {
      final presentation = PaperStatusPresentation.of(_paper(sourceFileUrl: null));
      expect(presentation.isMissingSource, isTrue);
      expect(presentation.label, 'Missing Source');
    });

    test('UNDER_REVIEW is displayed as Needs Review', () {
      final presentation = PaperStatusPresentation.of(_paper(contentStatus: 'UNDER_REVIEW'));
      expect(presentation.label, 'Needs Review');
    });

    test('a DRAFT paper that already has a source file is just Draft, not Missing Source', () {
      final presentation = PaperStatusPresentation.of(_paper(contentStatus: 'DRAFT'));
      expect(presentation.isMissingSource, isFalse);
      expect(presentation.label, 'Draft');
    });
  });
}
