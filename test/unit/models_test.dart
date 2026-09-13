import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/constants/app_constants.dart';
import 'package:induction_program_past_papers/data/models/paper.dart';
import 'package:induction_program_past_papers/data/models/question.dart';
import 'package:induction_program_past_papers/data/models/user_progress.dart';

void main() {
  group('Paper', () {
    test('parses from JSON and never expects a year field', () {
      final json = {
        'id': 'p1',
        'phase_id': 'ph1',
        'subject_id': 's1',
        'title': 'English Paper',
        'cadre': null,
        'total_marks': 100,
        'duration_minutes': 90,
        'source_file_url': null,
        'source_file_type': null,
        'content_status': 'PUBLISHED',
        'verification_status': 'VERIFIED',
        'version': 1,
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-01-01T00:00:00Z',
      };
      final paper = Paper.fromJson(json);
      expect(paper.isPublished, isTrue);
      expect(paper.toJson().containsKey('year'), isFalse);
    });
  });

  group('Question quality/answer discrepancy', () {
    test('flags PAPER_ANSWER_ERROR as a discrepancy requiring review', () {
      final question = Question(
        id: 'q1',
        paperSectionId: 'sec1',
        questionNumber: 5,
        questionType: QuestionType.mcq,
        questionText: 'Identify the compound word.',
        originalMarkedOption: 'B',
        verifiedAnswer: 'C',
        verificationStatus: 'PAPER_ANSWER_ERROR',
        qualityStatus: QualityStatus.answerUncertain,
        displayOrder: 0,
      );
      expect(question.hasAnswerKeyDiscrepancy, isTrue);
    });

    test('VERIFIED questions do not require a warning badge', () {
      final question = Question(
        id: 'q2',
        paperSectionId: 'sec1',
        questionNumber: 1,
        questionType: QuestionType.mcq,
        questionText: 'Sample',
        verificationStatus: 'VERIFIED',
        qualityStatus: QualityStatus.verified,
        displayOrder: 0,
      );
      expect(question.qualityStatus.requiresWarningBadge, isFalse);
    });

    test('QUESTIONABLE questions require a warning badge', () {
      expect(QualityStatus.questionable.requiresWarningBadge, isTrue);
      expect(QualityStatus.paperError.requiresWarningBadge, isTrue);
      expect(QualityStatus.ocrUncertain.requiresWarningBadge, isTrue);
      expect(QualityStatus.answerUncertain.requiresWarningBadge, isTrue);
    });
  });

  group('UserProgress accuracy', () {
    test('accuracyPercentage avoids division by zero when nothing attempted', () {
      final progress = UserProgress(
        id: 'up1',
        userId: 'u1',
        phaseId: 'ph1',
        subjectId: 's1',
        attemptedCount: 0,
        correctCount: 0,
        incorrectCount: 0,
        completedPapersCount: 0,
        updatedAt: DateTime.now(),
      );
      expect(progress.accuracyPercentage, 0);
    });

    test('computes accuracy percentage correctly', () {
      final progress = UserProgress(
        id: 'up1',
        userId: 'u1',
        phaseId: 'ph1',
        subjectId: 's1',
        attemptedCount: 20,
        correctCount: 17,
        incorrectCount: 3,
        completedPapersCount: 1,
        updatedAt: DateTime.now(),
      );
      expect(progress.accuracyPercentage, 85.0);
    });
  });

  group('AppConstants structural rules', () {
    test('exactly 3 phases and 8 subjects are defined', () {
      expect(AppConstants.phaseSlugs.length, 3);
      expect(AppConstants.subjectSlugs.length, 8);
      expect(AppConstants.totalExpectedPapers, 24);
    });
  });
}
