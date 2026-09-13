import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/phase.dart';
import '../../data/models/subject.dart';
import '../../shared/widgets/state_widgets.dart';

final subjectsProvider = FutureProvider<List<Subject>>((ref) {
  return ref.read(subjectRepositoryProvider).getSubjects();
});

final _subjectIcons = <String, IconData>{
  'english': Icons.translate_outlined,
  'mathematics': Icons.calculate_outlined,
  'general-science': Icons.science_outlined,
  'islamiat-nazra-quran': Icons.mosque_outlined,
  'ict-in-education': Icons.computer_outlined,
  'classroom-management-assessment': Icons.groups_outlined,
  'educational-psychology': Icons.psychology_outlined,
  'curriculum-and-instruction': Icons.menu_book_outlined,
};

class PhaseScreen extends ConsumerWidget {
  final String phaseId;
  const PhaseScreen({super.key, required this.phaseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phasesAsync = ref.watch(_phaseByIdProvider(phaseId));
    final subjectsAsync = ref.watch(subjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: phasesAsync.maybeWhen(
          data: (phase) => Text(phase?.name ?? 'Phase'),
          orElse: () => const Text('Phase'),
        ),
      ),
      body: subjectsAsync.when(
        data: (subjects) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: subjects.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final subject = subjects[index];
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/subject/${subject.id}?phaseId=$phaseId'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _subjectIcons[subject.slug] ?? Icons.book_outlined,
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(subject.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        loading: () => const LoadingList(itemCount: 8),
        error: (e, st) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(subjectsProvider),
        ),
      ),
    );
  }
}

final _phaseByIdProvider =
    FutureProvider.family<Phase?, String>((ref, phaseId) async {
  final phases = await ref.watch(_allPhasesProvider.future);
  for (final phase in phases) {
    if (phase.id == phaseId) return phase;
  }
  return null;
});

final _allPhasesProvider = FutureProvider<List<Phase>>((ref) {
  return ref.read(phaseRepositoryProvider).getPhases();
});
