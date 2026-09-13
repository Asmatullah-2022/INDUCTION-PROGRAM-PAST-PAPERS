import '../../data/models/question.dart';

/// Pure reordering logic for the Section Editor's drag-to-reorder feature.
/// Moving a question changes its position/number only — never its id —
/// see CLAUDE.md: "Reordering must change order/position, NOT create new
/// questions."
class QuestionReorder {
  QuestionReorder._();

  /// Moves the question currently at [oldIndex] to [newIndex] (both
  /// already the final, UI-quirk-adjusted indices — see the caller in
  /// AdminQuestionsScreen for the ReorderableListView index adjustment),
  /// then renumbers every question sequentially to match the new order.
  static List<Question> moveAndRenumber({
    required List<Question> questions,
    required int oldIndex,
    required int newIndex,
  }) {
    final list = List<Question>.from(questions);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    return renumberSequentially(list);
  }

  /// Assigns question_number 1..n and display_order 0..n-1 to match
  /// [questions]' current order — every question keeps its id and every
  /// other field untouched.
  static List<Question> renumberSequentially(List<Question> questions) {
    return [
      for (var i = 0; i < questions.length; i++)
        questions[i].copyWith(questionNumber: i + 1, displayOrder: i),
    ];
  }
}
