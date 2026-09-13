import '../../data/models/question.dart';

class PracticeQuestionResult {
  final Question question;
  final String? selectedOptionLabel;
  final bool isSkipped;

  const PracticeQuestionResult({
    required this.question,
    required this.selectedOptionLabel,
    required this.isSkipped,
  });

  bool get isCorrect {
    if (isSkipped || selectedOptionLabel == null) return false;
    final correctOption = question.options.where((o) => o.isVerifiedCorrect).toList();
    if (correctOption.isEmpty) return false;
    return correctOption.first.optionLabel == selectedOptionLabel;
  }
}

class PracticeResult {
  final String phaseId;
  final String subjectId;
  final List<PracticeQuestionResult> results;

  const PracticeResult({
    required this.phaseId,
    required this.subjectId,
    required this.results,
  });

  int get total => results.length;
  int get correct => results.where((r) => r.isCorrect).length;
  int get skipped => results.where((r) => r.isSkipped).length;
  int get incorrect => total - correct - skipped;
  double get percentage => total == 0 ? 0 : (correct / total) * 100;
}
