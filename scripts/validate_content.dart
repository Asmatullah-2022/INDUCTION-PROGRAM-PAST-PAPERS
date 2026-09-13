// Content validation script.
//
// Usage: dart run scripts/validate_content.dart [content_dir]
// Defaults to ./content
//
// Validates every phase_*/*.json file against the rules in spec section 57
// before it is allowed into the importer. Exits with a non-zero code if any
// CRITICAL error is found, so this can gate CI / the import pipeline.
//
// Expected JSON shape per file (one file = one paper):
// {
//   "phase_slug": "phase-4",
//   "subject_slug": "english",
//   "title": "...",
//   "total_marks": 100,
//   "duration_minutes": 90,
//   "sections": [
//     {
//       "section_name": "Section A",
//       "section_code": "A",
//       "marks": 20,
//       "questions": [
//         {
//           "question_number": 1,
//           "question_type": "mcq",
//           "question_text": "...",
//           "marks": 1,
//           "quality_status": "VERIFIED",
//           "options": [
//             {"option_label": "A", "option_text": "...", "is_verified_correct": false},
//             ...
//           ]
//         }
//       ]
//     }
//   ]
// }

import 'dart:convert';
import 'dart:io';

import 'package:induction_program_past_papers/core/constants/app_constants.dart';
import 'package:induction_program_past_papers/core/validation/question_numbering.dart';

// Single source of truth: these come from the same lib/core/constants and
// lib/core/validation the Flutter app itself uses (AppConstants,
// QuestionNumberingValidator), rather than a second, hand-maintained copy
// that could silently drift from the app's own rules. If a phase/subject
// slug or numbering rule ever changes, it changes here automatically too.
final validPhaseSlugs = AppConstants.phaseSlugs.toSet();
final validSubjectSlugs = AppConstants.subjectSlugs.toSet();
final validQuestionTypes = QuestionType.values.map((t) => t.dbValue).toSet();
final validQualityStatuses = QualityStatus.values.map((q) => q.dbValue).toSet();

class ValidationError {
  final String file;
  final String message;
  final bool critical;
  ValidationError(this.file, this.message, {this.critical = true});

  @override
  String toString() => '${critical ? "CRITICAL" : "WARNING"} [$file]: $message';
}

void main(List<String> args) {
  final contentDir = Directory(args.isNotEmpty ? args[0] : 'content');
  if (!contentDir.existsSync()) {
    stderr.writeln('Content directory not found: ${contentDir.path}');
    exit(2);
  }

  final files = contentDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList();

  if (files.isEmpty) {
    stdout.writeln(
      'No content files found under ${contentDir.path}. '
      'This is expected until verified source papers are supplied — '
      'nothing to validate. MISSING SOURCE PAPER — DO NOT PUBLISH.',
    );
    exit(0);
  }

  final errors = <ValidationError>[];
  final seenPaperSlots = <String>{};

  for (final file in files) {
    _validateFile(file, errors, seenPaperSlots);
  }

  for (final e in errors) {
    stdout.writeln(e);
  }

  final criticalCount = errors.where((e) => e.critical).length;
  stdout.writeln(
    '\nValidated ${files.length} file(s): '
    '${errors.length - criticalCount} warning(s), $criticalCount critical error(s).',
  );

  if (criticalCount > 0) {
    stdout.writeln('FAILED — critical errors must be fixed before import.');
    exit(1);
  }
  stdout.writeln('PASSED — no critical errors found.');
}

void _validateFile(File file, List<ValidationError> errors, Set<String> seenPaperSlots) {
  final path = file.path;
  Map<String, dynamic> paper;
  try {
    paper = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    errors.add(ValidationError(path, 'Invalid JSON: $e'));
    return;
  }

  final phaseSlug = paper['phase_slug'] as String?;
  final subjectSlug = paper['subject_slug'] as String?;

  if (phaseSlug == null || !validPhaseSlugs.contains(phaseSlug)) {
    errors.add(ValidationError(path, 'Invalid or missing phase_slug: $phaseSlug'));
  }
  if (subjectSlug == null || !validSubjectSlugs.contains(subjectSlug)) {
    errors.add(ValidationError(path, 'Invalid or missing subject_slug: $subjectSlug'));
  }
  if (paper.containsKey('year') ||
      paper.containsKey('academic_year') ||
      paper.containsKey('session_year')) {
    errors.add(ValidationError(
        path, 'A year-based field is present — this app has NO year concept.'));
  }

  if (phaseSlug != null && subjectSlug != null) {
    final slot = '$phaseSlug::$subjectSlug';
    if (!seenPaperSlots.add(slot)) {
      errors.add(ValidationError(path, 'Duplicate paper for phase/subject slot: $slot'));
    }
  }

  final totalMarks = paper['total_marks'];
  if (totalMarks != null && (totalMarks is! num || totalMarks <= 0)) {
    errors.add(ValidationError(path, 'Invalid total_marks: $totalMarks'));
  }

  final sections = paper['sections'];
  if (sections is! List || sections.isEmpty) {
    errors.add(ValidationError(path, 'Paper has no sections.'));
    return;
  }

  for (final rawSection in sections) {
    if (rawSection is! Map<String, dynamic>) {
      errors.add(ValidationError(path, 'Section entry is not an object.'));
      continue;
    }
    final sectionCode = rawSection['section_code'] as String? ?? '?';
    final questions = rawSection['questions'];
    if (questions is! List || questions.isEmpty) {
      errors.add(ValidationError(
          path, 'Section $sectionCode has no questions.', critical: false));
      continue;
    }

    // Duplicate/gap detection is not re-implemented here — see
    // QuestionNumberingValidator, the one canonical place for this rule,
    // also used live by the admin Section Editor and by
    // PaperQualityChecker's paper-wide quality report.
    final numbers = questions
        .whereType<Map<String, dynamic>>()
        .map((q) => q['question_number'])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    final numberingReport = QuestionNumberingValidator.check(numbers);
    for (final issue in numberingReport.issues) {
      errors.add(ValidationError(
        path,
        'Section $sectionCode: ${issue.message}',
        critical: issue.severity == NumberingIssueSeverity.error,
      ));
    }

    for (final rawQuestion in questions) {
      _validateQuestion(path, sectionCode, rawQuestion, errors);
    }
  }
}

void _validateQuestion(
  String path,
  String sectionCode,
  dynamic rawQuestion,
  List<ValidationError> errors,
) {
  if (rawQuestion is! Map<String, dynamic>) {
    errors.add(ValidationError(path, 'Question entry in section $sectionCode is not an object.'));
    return;
  }

  final questionNumber = rawQuestion['question_number'];
  final questionType = rawQuestion['question_type'] as String?;
  final questionText = rawQuestion['question_text'] as String?;
  final qualityStatus = rawQuestion['quality_status'] as String?;
  final marks = rawQuestion['marks'];

  final label = 'Section $sectionCode Q${questionNumber ?? '?'}';

  if (questionNumber == null || questionNumber is! num) {
    errors.add(ValidationError(path, '$label: missing/invalid question_number.'));
  }

  if (questionType == null || !validQuestionTypes.contains(questionType)) {
    errors.add(ValidationError(path, '$label: invalid question_type "$questionType".'));
  }

  if (questionText == null || questionText.trim().isEmpty) {
    errors.add(ValidationError(path, '$label: empty question_text.'));
  }

  if (qualityStatus == null || !validQualityStatuses.contains(qualityStatus)) {
    errors.add(ValidationError(path, '$label: missing/invalid quality_status.'));
  }

  if (marks != null && (marks is! num || marks < 0)) {
    errors.add(ValidationError(path, '$label: invalid marks value "$marks".'));
  }

  if (questionType == 'mcq') {
    final options = rawQuestion['options'];
    if (options is! List || options.length < 2) {
      errors.add(ValidationError(path, '$label: MCQ must have at least 2 options.'));
    } else {
      var correctCount = 0;
      final seenLabels = <String>{};
      for (final rawOption in options) {
        if (rawOption is! Map<String, dynamic>) {
          errors.add(ValidationError(path, '$label: an option entry is not an object.'));
          continue;
        }
        final optionLabel = rawOption['option_label'] as String?;
        final optionText = rawOption['option_text'] as String?;
        if (optionLabel == null || optionLabel.trim().isEmpty) {
          errors.add(ValidationError(path, '$label: option missing option_label.'));
        } else if (!seenLabels.add(optionLabel)) {
          errors.add(ValidationError(path, '$label: duplicate option_label "$optionLabel".'));
        }
        if (optionText == null || optionText.trim().isEmpty) {
          errors.add(ValidationError(path, '$label: option missing option_text.'));
        }
        if (rawOption['is_verified_correct'] == true) correctCount++;
      }
      if (correctCount == 0) {
        errors.add(ValidationError(path, '$label: no option marked is_verified_correct.'));
      } else if (correctCount > 1) {
        errors.add(ValidationError(
            path, '$label: more than one option marked is_verified_correct.'));
      }
    }
  } else {
    // short / long questions must carry a verified answer.
    final verifiedAnswer = rawQuestion['verified_answer'] as String?;
    if (verifiedAnswer == null || verifiedAnswer.trim().isEmpty) {
      errors.add(ValidationError(path, '$label: missing verified_answer.'));
    }
  }

  if (qualityStatus != null && qualityStatus != 'VERIFIED') {
    final note = rawQuestion['quality_note'] as String?;
    if (note == null || note.trim().isEmpty) {
      errors.add(ValidationError(
        path,
        '$label: quality_status "$qualityStatus" requires a quality_note explaining why.',
      ));
    }
  }
}
