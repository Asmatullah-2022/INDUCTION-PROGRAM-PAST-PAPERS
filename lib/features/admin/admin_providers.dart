import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/paper.dart';
import '../../data/models/paper_section.dart';
import '../../data/models/question.dart';

final adminAllPapersProvider = FutureProvider<List<Paper>>((ref) {
  return ref.read(adminRepositoryProvider).getAllPapers();
});

final adminSectionsProvider = FutureProvider.family<List<PaperSection>, String>((ref, paperId) {
  return ref.read(adminRepositoryProvider).getSections(paperId);
});

final adminQuestionsProvider = FutureProvider.family<List<Question>, String>((ref, sectionId) {
  return ref.read(adminRepositoryProvider).getQuestions(sectionId);
});

final adminQuestionProvider = FutureProvider.family<Question, String>((ref, questionId) {
  return ref.read(adminRepositoryProvider).getQuestion(questionId);
});

final adminQuestionableQuestionsProvider = FutureProvider<List<Question>>((ref) {
  return ref.read(adminRepositoryProvider).getQuestionableQuestions();
});
