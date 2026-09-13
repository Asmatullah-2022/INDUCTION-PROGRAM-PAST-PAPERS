import '../constants/app_constants.dart';
import 'question_numbering.dart';

/// Validates one paper's JSON (the same shape `scripts/validate_content.dart`
/// and `scripts/import_content.dart` use — see `docs/CONTENT_IMPORT_GUIDE.md`)
/// before it's imported through the in-app Bulk Import screen. This is the
/// same rule set as the standalone script, sharing the phase/subject slugs
/// and `QuestionNumberingValidator` from `lib/core/constants`/
/// `lib/core/validation` so the two paths can't silently drift — see
/// CLAUDE.md "Testing Rules".
///
/// The script remains authoritative for file-based/CI import (it has no
/// Flutter dependency and works before any Supabase session exists); this
/// class is for the admin-authenticated, in-app alternative, which writes
/// through the same RLS-gated AdminRepository as every other admin screen
/// rather than a service-role key.
class ContentImportIssue {
  final bool critical;
  final String message;

  const ContentImportIssue({required this.critical, required this.message});

  @override
  String toString() => '${critical ? "CRITICAL" : "WARNING"}: $message';
}

class ContentImportReport {
  final List<ContentImportIssue> issues;

  const ContentImportReport({required this.issues});

  bool get hasCriticalErrors => issues.any((i) => i.critical);
  List<ContentImportIssue> get errors => issues.where((i) => i.critical).toList();
  List<ContentImportIssue> get warnings => issues.where((i) => !i.critical).toList();
}

class ContentImportValidator {
  ContentImportValidator._();

  static final _validPhaseSlugs = AppConstants.phaseSlugs.toSet();
  static final _validSubjectSlugs = AppConstants.subjectSlugs.toSet();
  static final _validQuestionTypes = QuestionType.values.map((t) => t.dbValue).toSet();
  static final _validQualityStatuses = QualityStatus.values.map((q) => q.dbValue).toSet();

  static ContentImportReport validate(Map<String, dynamic> paper) {
    final issues = <ContentImportIssue>[];

    final phaseSlug = paper['phase_slug'] as String?;
    final subjectSlug = paper['subject_slug'] as String?;

    if (phaseSlug == null || !_validPhaseSlugs.contains(phaseSlug)) {
      issues.add(ContentImportIssue(
          critical: true, message: 'Invalid or missing phase_slug: $phaseSlug'));
    }
    if (subjectSlug == null || !_validSubjectSlugs.contains(subjectSlug)) {
      issues.add(ContentImportIssue(
          critical: true, message: 'Invalid or missing subject_slug: $subjectSlug'));
    }
    if (paper.containsKey('year') ||
        paper.containsKey('academic_year') ||
        paper.containsKey('session_year')) {
      issues.add(const ContentImportIssue(
        critical: true,
        message: 'A year-based field is present — this app has NO year concept.',
      ));
    }
    if (paper['title'] == null || (paper['title'] as String).trim().isEmpty) {
      issues.add(const ContentImportIssue(critical: true, message: 'Missing title.'));
    }

    final totalMarks = paper['total_marks'];
    if (totalMarks != null && (totalMarks is! num || totalMarks <= 0)) {
      issues.add(ContentImportIssue(critical: true, message: 'Invalid total_marks: $totalMarks'));
    }

    final sections = paper['sections'];
    if (sections is! List || sections.isEmpty) {
      issues.add(const ContentImportIssue(critical: true, message: 'Paper has no sections.'));
      return ContentImportReport(issues: issues);
    }

    for (final rawSection in sections) {
      if (rawSection is! Map<String, dynamic>) {
        issues.add(const ContentImportIssue(
            critical: true, message: 'A section entry is not an object.'));
        continue;
      }
      _validateSection(rawSection, issues);
    }

    return ContentImportReport(issues: issues);
  }

  static void _validateSection(Map<String, dynamic> section, List<ContentImportIssue> issues) {
    final sectionCode = section['section_code'] as String? ?? '?';
    if (section['section_name'] == null ||
        (section['section_name'] as String).trim().isEmpty) {
      issues.add(ContentImportIssue(
          critical: true, message: 'Section $sectionCode is missing section_name.'));
    }

    final questions = section['questions'];
    if (questions is! List || questions.isEmpty) {
      issues.add(ContentImportIssue(
          critical: false, message: 'Section $sectionCode has no questions.'));
      return;
    }

    final numbers = questions
        .whereType<Map<String, dynamic>>()
        .map((q) => q['question_number'])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    final numberingReport = QuestionNumberingValidator.check(numbers);
    for (final issue in numberingReport.issues) {
      issues.add(ContentImportIssue(
        critical: issue.severity == NumberingIssueSeverity.error,
        message: 'Section $sectionCode: ${issue.message}',
      ));
    }

    for (final rawQuestion in questions) {
      _validateQuestion(sectionCode, rawQuestion, issues);
    }
  }

  static void _validateQuestion(
    String sectionCode,
    dynamic rawQuestion,
    List<ContentImportIssue> issues,
  ) {
    if (rawQuestion is! Map<String, dynamic>) {
      issues.add(ContentImportIssue(
          critical: true, message: 'A question entry in section $sectionCode is not an object.'));
      return;
    }

    final questionNumber = rawQuestion['question_number'];
    final questionType = rawQuestion['question_type'] as String?;
    final questionText = rawQuestion['question_text'] as String?;
    final qualityStatus = rawQuestion['quality_status'] as String?;
    final marks = rawQuestion['marks'];
    final label = 'Section $sectionCode Q${questionNumber ?? '?'}';

    if (questionNumber == null || questionNumber is! num) {
      issues.add(ContentImportIssue(critical: true, message: '$label: missing/invalid question_number.'));
    }
    if (questionType == null || !_validQuestionTypes.contains(questionType)) {
      issues.add(ContentImportIssue(
          critical: true, message: '$label: invalid question_type "$questionType".'));
    }
    if (questionText == null || questionText.trim().isEmpty) {
      issues.add(ContentImportIssue(critical: true, message: '$label: empty question_text.'));
    }
    if (qualityStatus == null || !_validQualityStatuses.contains(qualityStatus)) {
      issues.add(ContentImportIssue(critical: true, message: '$label: missing/invalid quality_status.'));
    }
    if (marks != null && (marks is! num || marks < 0)) {
      issues.add(ContentImportIssue(critical: true, message: '$label: invalid marks value "$marks".'));
    }

    if (questionType == 'mcq') {
      final options = rawQuestion['options'];
      if (options is! List || options.length < 2) {
        issues.add(ContentImportIssue(
            critical: true, message: '$label: MCQ must have at least 2 options.'));
      } else {
        var correctCount = 0;
        final seenLabels = <String>{};
        for (final rawOption in options) {
          if (rawOption is! Map<String, dynamic>) {
            issues.add(ContentImportIssue(
                critical: true, message: '$label: an option entry is not an object.'));
            continue;
          }
          final optionLabel = rawOption['option_label'] as String?;
          final optionText = rawOption['option_text'] as String?;
          if (optionLabel == null || optionLabel.trim().isEmpty) {
            issues.add(ContentImportIssue(
                critical: true, message: '$label: option missing option_label.'));
          } else if (!seenLabels.add(optionLabel)) {
            issues.add(ContentImportIssue(
                critical: true, message: '$label: duplicate option_label "$optionLabel".'));
          }
          if (optionText == null || optionText.trim().isEmpty) {
            issues.add(ContentImportIssue(
                critical: true, message: '$label: option missing option_text.'));
          }
          if (rawOption['is_verified_correct'] == true) correctCount++;
        }
        if (correctCount == 0) {
          issues.add(ContentImportIssue(
              critical: true, message: '$label: no option marked is_verified_correct.'));
        } else if (correctCount > 1) {
          issues.add(ContentImportIssue(
              critical: true, message: '$label: more than one option marked is_verified_correct.'));
        }
      }
    } else {
      final verifiedAnswer = rawQuestion['verified_answer'] as String?;
      if (verifiedAnswer == null || verifiedAnswer.trim().isEmpty) {
        issues.add(ContentImportIssue(critical: true, message: '$label: missing verified_answer.'));
      }
    }

    if (qualityStatus != null && qualityStatus != 'VERIFIED') {
      final note = rawQuestion['quality_note'] as String?;
      if (note == null || note.trim().isEmpty) {
        issues.add(ContentImportIssue(
          critical: true,
          message: '$label: quality_status "$qualityStatus" requires a quality_note explaining why.',
        ));
      }
    }
  }
}
