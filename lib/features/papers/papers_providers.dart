import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/paper.dart';
import '../../data/repositories/paper_repository.dart';

final paperByIdProvider = FutureProvider.family<Paper, String>(
  (ref, paperId) => ref.read(paperRepositoryProvider).getPaper(paperId),
);

final paperSectionsProvider =
    FutureProvider.family<List<SectionWithQuestions>, String>(
  (ref, paperId) =>
      ref.read(paperRepositoryProvider).getSectionsWithQuestions(paperId),
);
