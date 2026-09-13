import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/phase.dart';

final phasesProvider = FutureProvider<List<Phase>>((ref) {
  return ref.read(phaseRepositoryProvider).getPhases();
});
