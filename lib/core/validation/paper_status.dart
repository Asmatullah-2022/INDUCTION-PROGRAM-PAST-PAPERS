import '../../data/models/paper.dart';
import '../../data/models/paper_section.dart';
import '../../data/models/question.dart';
import '../constants/app_constants.dart';
import 'question_numbering.dart';

/// The 5 stored `papers.content_status` values (see
/// supabase/migrations/001_initial_schema.sql). "Missing Source" and
/// "Needs Review" are presentation labels only — see
/// [PaperStatusPresentation] — never new stored values, so existing rows
/// and the DB check constraint never need to change.
class PaperStatus {
  PaperStatus._();

  static const draft = 'DRAFT';
  static const underReview = 'UNDER_REVIEW';
  static const verified = 'VERIFIED';
  static const published = 'PUBLISHED';
  static const archived = 'ARCHIVED';

  static const all = [draft, underReview, verified, published, archived];
}

/// Client-side mirror of the `admin_transition_paper_status` Postgres
/// function's state machine (see migrations/006_admin_workflow.sql). This
/// copy exists only so the UI can disable invalid actions and fail fast
/// with a clear message; the database function is the actual authority —
/// a client bypassing this class entirely still can't perform an illegal
/// transition, because the RPC re-checks it server-side.
class PaperStatusTransitions {
  PaperStatusTransitions._();

  static const Map<String, List<String>> _allowed = {
    PaperStatus.draft: [PaperStatus.underReview, PaperStatus.archived],
    PaperStatus.underReview: [PaperStatus.draft, PaperStatus.verified, PaperStatus.archived],
    PaperStatus.verified: [PaperStatus.underReview, PaperStatus.published, PaperStatus.archived],
    PaperStatus.published: [PaperStatus.verified, PaperStatus.archived],
    PaperStatus.archived: [PaperStatus.draft],
  };

  static bool isAllowed(String current, String next) {
    if (current == next) return true;
    return _allowed[current]?.contains(next) ?? false;
  }

  static List<String> allowedNextStatuses(String current) =>
      List.unmodifiable(_allowed[current] ?? const []);
}

enum QualityIssueSeverity { error, warning }

class QualityIssue {
  final QualityIssueSeverity severity;
  final String message;
  final String? questionId;

  const QualityIssue({required this.severity, required this.message, this.questionId});
}

enum QualityCategory { pass, warning, error }

/// A paper's aggregate quality report — the client-side mirror of
/// `paper_has_critical_errors` in 006_admin_workflow.sql, extended with a
/// 0-100 score and warnings (which the DB gate doesn't need, since it only
/// has to decide pass/fail, not present a report to a human).
class PaperQualityReport {
  final List<QualityIssue> errors;
  final List<QualityIssue> warnings;

  const PaperQualityReport({required this.errors, required this.warnings});

  bool get hasCriticalErrors => errors.isNotEmpty;

  int get score {
    final penalty = errors.length * 15 + warnings.length * 5;
    return (100 - penalty).clamp(0, 100);
  }

  QualityCategory get category {
    if (errors.isNotEmpty) return QualityCategory.error;
    if (warnings.isNotEmpty) return QualityCategory.warning;
    return QualityCategory.pass;
  }
}

/// One paper section paired with its questions, in the order they'll be
/// checked. Kept as a plain record here (rather than importing the
/// same-shaped class from data/repositories/paper_repository.dart) so this
/// core/ file only depends on data/models, never on data/repositories.
typedef SectionQuestions = ({PaperSection section, List<Question> questions});

/// Pure, side-effect-free paper-level quality gate — the client-side
/// mirror of `paper_has_critical_errors` in 006_admin_workflow.sql, used
/// to render the Paper Review screen's quality report and to pre-emptively
/// disable the Verify/Publish actions. The database function remains the
/// real authority (see PaperStatusTransitions doc comment).
class PaperQualityChecker {
  PaperQualityChecker._();

  static PaperQualityReport check({
    required Paper paper,
    required List<SectionQuestions> sections,
  }) {
    final errors = <QualityIssue>[];
    final warnings = <QualityIssue>[];

    if (paper.sourceFileUrl == null || paper.sourceFileUrl!.isEmpty) {
      errors.add(const QualityIssue(
        severity: QualityIssueSeverity.error,
        message: 'MISSING SOURCE PAPER — no original file has been uploaded.',
      ));
    }

    if (sections.isEmpty) {
      errors.add(const QualityIssue(
        severity: QualityIssueSeverity.error,
        message: 'This paper has no sections yet.',
      ));
      return PaperQualityReport(errors: errors, warnings: warnings);
    }

    for (final entry in sections) {
      final sectionCode = entry.section.sectionCode;
      final questions = entry.questions;

      if (questions.isEmpty) {
        errors.add(QualityIssue(
          severity: QualityIssueSeverity.error,
          message: 'Section $sectionCode has no questions.',
        ));
        continue;
      }

      // Duplicate/gap detection is not re-implemented here — see
      // QuestionNumberingValidator, the one canonical place for this rule,
      // also used live by the Section Editor.
      final numberingReport =
          QuestionNumberingValidator.check(questions.map((q) => q.questionNumber).toList());
      for (final issue in numberingReport.issues) {
        final isError = issue.severity == NumberingIssueSeverity.error;
        (isError ? errors : warnings).add(QualityIssue(
          severity: isError ? QualityIssueSeverity.error : QualityIssueSeverity.warning,
          message: 'Section $sectionCode: ${issue.message}',
        ));
      }

      for (final q in questions) {
        final label = 'Section $sectionCode Q${q.questionNumber}';

        if (q.questionText.trim().isEmpty) {
          errors.add(QualityIssue(
            severity: QualityIssueSeverity.error,
            message: '$label: question text is empty.',
            questionId: q.id,
          ));
        }

        if (q.questionType == QuestionType.mcq) {
          final correctCount = q.options.where((o) => o.isVerifiedCorrect).length;
          if (q.options.length < 2) {
            errors.add(QualityIssue(
              severity: QualityIssueSeverity.error,
              message: '$label: MCQ has fewer than 2 options.',
              questionId: q.id,
            ));
          }
          if (correctCount != 1) {
            errors.add(QualityIssue(
              severity: QualityIssueSeverity.error,
              message: '$label: MCQ does not have exactly one correct option.',
              questionId: q.id,
            ));
          }
        } else if (q.verifiedAnswer == null || q.verifiedAnswer!.trim().isEmpty) {
          errors.add(QualityIssue(
            severity: QualityIssueSeverity.error,
            message: '$label: missing a verified answer.',
            questionId: q.id,
          ));
        }

        if (q.marks != null && q.marks! < 0) {
          errors.add(QualityIssue(
            severity: QualityIssueSeverity.error,
            message: '$label: marks cannot be negative.',
            questionId: q.id,
          ));
        }

        if (q.qualityStatus != QualityStatus.verified) {
          warnings.add(QualityIssue(
            severity: QualityIssueSeverity.warning,
            message: '$label: quality status is ${q.qualityStatus.dbValue} — needs human review.',
            questionId: q.id,
          ));
        }
      }
    }

    return PaperQualityReport(errors: errors, warnings: warnings);
  }
}

/// How a paper's status should be *displayed* — folds in the derived
/// "Missing Source" state without adding a new stored status value.
class PaperStatusPresentation {
  final String label;
  final bool isMissingSource;

  const PaperStatusPresentation({required this.label, required this.isMissingSource});

  static PaperStatusPresentation of(Paper paper) {
    final missingSource = paper.sourceFileUrl == null || paper.sourceFileUrl!.isEmpty;
    if (missingSource && paper.contentStatus == PaperStatus.draft) {
      return const PaperStatusPresentation(label: 'Missing Source', isMissingSource: true);
    }
    final label = switch (paper.contentStatus) {
      PaperStatus.draft => 'Draft',
      PaperStatus.underReview => 'Needs Review',
      PaperStatus.verified => 'Verified',
      PaperStatus.published => 'Published',
      PaperStatus.archived => 'Archived',
      _ => paper.contentStatus,
    };
    return PaperStatusPresentation(label: label, isMissingSource: missingSource);
  }
}
