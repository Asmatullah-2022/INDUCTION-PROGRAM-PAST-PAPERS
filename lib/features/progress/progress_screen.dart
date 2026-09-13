import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/user_progress.dart';
import '../../shared/widgets/state_widgets.dart';
import '../phases/phase_screen.dart' show subjectsProvider;

final myProgressProvider = FutureProvider<List<UserProgress>>((ref) {
  return ref.read(progressRepositoryProvider).getMyProgress();
});

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(myProgressProvider);
    final subjectsAsync = ref.watch(subjectsProvider);
    final subjectNames = subjectsAsync.maybeWhen(
      data: (subjects) => {for (final s in subjects) s.id: s.name},
      orElse: () => <String, String>{},
    );

    return Scaffold(
      appBar: AppBar(title: const Text('My Progress')),
      body: progressAsync.when(
        data: (progressList) {
          if (progressList.isEmpty) {
            return const EmptyState(
              icon: Icons.trending_up,
              title: 'No practice attempts yet',
              subtitle: 'Complete a practice session to start tracking your progress.',
            );
          }
          final byPhase = <String, List<UserProgress>>{};
          for (final p in progressList) {
            byPhase.putIfAbsent(p.phaseId, () => []).add(p);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: byPhase.entries.map((entry) {
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Phase', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 8),
                      ...entry.value.map((p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(subjectNames[p.subjectId] ?? 'Subject'),
                                    Text('${p.accuracyPercentage.toStringAsFixed(0)}%',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: p.accuracyPercentage / 100,
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
        loading: () => const LoadingList(),
        error: (e, st) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(myProgressProvider),
        ),
      ),
    );
  }
}
