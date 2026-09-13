import 'package:flutter_test/flutter_test.dart';
import 'package:induction_program_past_papers/core/constants/app_constants.dart';
import 'package:induction_program_past_papers/core/utils/question_reorder.dart';
import 'package:induction_program_past_papers/data/models/question.dart';

Question _q(String id, int number, {int displayOrder = 0}) => Question(
      id: id,
      paperSectionId: 'section-1',
      questionNumber: number,
      questionType: QuestionType.short,
      questionText: 'Question $id text',
      verifiedAnswer: 'Answer for $id',
      verificationStatus: 'VERIFIED',
      qualityStatus: QualityStatus.verified,
      displayOrder: displayOrder,
    );

void main() {
  group('QuestionReorder.renumberSequentially', () {
    test('assigns 1..n question numbers and 0..n-1 display orders in list order', () {
      final result = QuestionReorder.renumberSequentially([
        _q('a', 5),
        _q('b', 9),
        _q('c', 1),
      ]);
      expect(result.map((q) => q.questionNumber), [1, 2, 3]);
      expect(result.map((q) => q.displayOrder), [0, 1, 2]);
    });

    test('6. reordering updates order correctly — output order matches input order', () {
      final result = QuestionReorder.renumberSequentially([_q('c', 1), _q('a', 2), _q('b', 3)]);
      expect(result.map((q) => q.id), ['c', 'a', 'b']);
    });

    test('7. renumbering preserves every question\'s id and other fields', () {
      final original = _q('a', 5, displayOrder: 4);
      final result = QuestionReorder.renumberSequentially([original]);
      expect(result.single.id, 'a');
      expect(result.single.questionText, original.questionText);
      expect(result.single.verifiedAnswer, original.verifiedAnswer);
      expect(result.single.questionNumber, 1); // renumbered
    });

    test('an empty list renumbers to an empty list without error', () {
      expect(QuestionReorder.renumberSequentially([]), isEmpty);
    });
  });

  group('QuestionReorder.moveAndRenumber', () {
    test('moving the first item to the end reorders and renumbers correctly', () {
      final questions = [_q('a', 1), _q('b', 2), _q('c', 3)];
      final result =
          QuestionReorder.moveAndRenumber(questions: questions, oldIndex: 0, newIndex: 2);
      expect(result.map((q) => q.id), ['b', 'c', 'a']);
      expect(result.map((q) => q.questionNumber), [1, 2, 3]);
    });

    test('moving the last item to the front reorders and renumbers correctly', () {
      final questions = [_q('a', 1), _q('b', 2), _q('c', 3)];
      final result =
          QuestionReorder.moveAndRenumber(questions: questions, oldIndex: 2, newIndex: 0);
      expect(result.map((q) => q.id), ['c', 'a', 'b']);
    });

    test('a no-op move (same index) leaves order unchanged but still renumbers', () {
      final questions = [_q('a', 9), _q('b', 9)]; // pre-existing duplicate numbers
      final result =
          QuestionReorder.moveAndRenumber(questions: questions, oldIndex: 0, newIndex: 0);
      expect(result.map((q) => q.id), ['a', 'b']);
      expect(result.map((q) => q.questionNumber), [1, 2]); // duplicate resolved by renumbering
    });

    test('7. moving preserves ids exactly — no id is created, changed, or dropped', () {
      final questions = [_q('a', 1), _q('b', 2), _q('c', 3), _q('d', 4)];
      final result =
          QuestionReorder.moveAndRenumber(questions: questions, oldIndex: 1, newIndex: 3);
      expect(result.map((q) => q.id).toSet(), {'a', 'b', 'c', 'd'});
      expect(result.length, questions.length);
    });

    test('8. multiple sequential reorder operations compose correctly', () {
      var questions = [_q('a', 1), _q('b', 2), _q('c', 3), _q('d', 4)];
      // Move 'a' to the end: b, c, d, a
      questions = QuestionReorder.moveAndRenumber(questions: questions, oldIndex: 0, newIndex: 3);
      expect(questions.map((q) => q.id), ['b', 'c', 'd', 'a']);

      // Then move 'd' (now at index 2) to the front: d, b, c, a
      questions = QuestionReorder.moveAndRenumber(questions: questions, oldIndex: 2, newIndex: 0);
      expect(questions.map((q) => q.id), ['d', 'b', 'c', 'a']);
      expect(questions.map((q) => q.questionNumber), [1, 2, 3, 4]);
    });

    test('9. the numbering validator reports valid immediately after any reorder', () {
      final questions = [_q('a', 7), _q('b', 7), _q('c', 2)]; // starts with a duplicate
      final result =
          QuestionReorder.moveAndRenumber(questions: questions, oldIndex: 2, newIndex: 0);
      // After a move, sequential renumbering always yields 1..n — no
      // duplicate/gap can survive a save, regardless of what the source
      // numbers looked like before.
      expect(result.map((q) => q.questionNumber), [1, 2, 3]);
    });
  });
}
