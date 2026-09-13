/// Pure numbering validation for a single section's questions — the one
/// canonical place this logic lives, shared by the Section Editor's live
/// validation, PaperQualityChecker (paper-wide quality report), and
/// available to the content validator/import pipeline for the same rule.
/// Never re-implement duplicate/gap detection inline elsewhere — see
/// CLAUDE.md "Testing Rules".
library;

enum NumberingIssueSeverity { error, warning }

class NumberingIssue {
  final NumberingIssueSeverity severity;
  final String message;

  const NumberingIssue({required this.severity, required this.message});
}

/// The result of checking one section's question numbers.
///
/// Duplicate numbers are always an [NumberingIssueSeverity.error] — two
/// questions cannot legitimately share a number. A numbering gap (e.g.
/// 1, 2, 4, 5 — no question 3) is only a [NumberingIssueSeverity.warning]:
/// real source papers occasionally skip a number (a removed/voided
/// question), so a gap alone shouldn't block anything, but it's still
/// worth an admin's attention.
class QuestionNumberingReport {
  final List<NumberingIssue> issues;

  const QuestionNumberingReport({required this.issues});

  bool get isValid => issues.isEmpty;
  bool get hasErrors => issues.any((i) => i.severity == NumberingIssueSeverity.error);
  List<NumberingIssue> get errors =>
      issues.where((i) => i.severity == NumberingIssueSeverity.error).toList();
  List<NumberingIssue> get warnings =>
      issues.where((i) => i.severity == NumberingIssueSeverity.warning).toList();
}

class QuestionNumberingValidator {
  QuestionNumberingValidator._();

  /// [numbers] should be every question_number currently in one section,
  /// in any order — duplicates and gaps are detected regardless of input
  /// order.
  static QuestionNumberingReport check(List<int> numbers) {
    final issues = <NumberingIssue>[];
    if (numbers.isEmpty) return const QuestionNumberingReport(issues: []);

    final counts = <int, int>{};
    for (final n in numbers) {
      counts[n] = (counts[n] ?? 0) + 1;
    }

    final duplicates = counts.entries.where((e) => e.value > 1).map((e) => e.key).toList()
      ..sort();
    for (final n in duplicates) {
      issues.add(NumberingIssue(
        severity: NumberingIssueSeverity.error,
        message: 'Duplicate question number: $n',
      ));
    }

    final distinct = counts.keys.toList()..sort();
    final min = distinct.first;
    final max = distinct.last;
    for (var n = min; n <= max; n++) {
      if (!counts.containsKey(n)) {
        issues.add(NumberingIssue(
          severity: NumberingIssueSeverity.warning,
          message: 'Missing question number: $n',
        ));
      }
    }

    return QuestionNumberingReport(issues: issues);
  }
}
