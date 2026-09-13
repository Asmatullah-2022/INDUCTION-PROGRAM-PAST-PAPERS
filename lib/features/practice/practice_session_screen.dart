import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/question.dart';
import '../../shared/widgets/state_widgets.dart';
import 'practice_result.dart';

final practiceQuestionsProvider = FutureProvider.family<List<Question>,
    ({String phaseId, String subjectId, int? limit})>((ref, args) {
  return ref.read(practiceRepositoryProvider).getPracticeQuestions(
        phaseId: args.phaseId,
        subjectId: args.subjectId,
        limit: args.limit,
      );
});

class PracticeSessionScreen extends ConsumerStatefulWidget {
  final String phaseId;
  final String subjectId;
  final int? limit;

  const PracticeSessionScreen({
    super.key,
    required this.phaseId,
    required this.subjectId,
    this.limit,
  });

  @override
  ConsumerState<PracticeSessionScreen> createState() => _PracticeSessionScreenState();
}

class _PracticeSessionScreenState extends ConsumerState<PracticeSessionScreen> {
  int _currentIndex = 0;
  final Map<int, String?> _selectedOptions = {};

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(practiceQuestionsProvider(
      (phaseId: widget.phaseId, subjectId: widget.subjectId, limit: widget.limit),
    ));

    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: questionsAsync.when(
        data: (questions) {
          if (questions.isEmpty) {
            return const EmptyState(
              icon: Icons.quiz_outlined,
              title: 'No published MCQs available for practice yet',
            );
          }
          final question = questions[_currentIndex];
          final selected = _selectedOptions[_currentIndex];

          return Column(
            children: [
              LinearProgressIndicator(value: (_currentIndex + 1) / questions.length),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Question ${_currentIndex + 1} of ${questions.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.questionText,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 20),
                      ...question.options.map((o) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(
                                  () => _selectedOptions[_currentIndex] = o.optionLabel),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected == o.optionLabel
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.outlineVariant,
                                    width: selected == o.optionLabel ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: selected == o.optionLabel
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                      child: Text(o.optionLabel,
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(o.optionText)),
                                  ],
                                ),
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (_currentIndex > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _currentIndex--),
                          child: const Text('Previous'),
                        ),
                      ),
                    if (_currentIndex > 0) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (_currentIndex < questions.length - 1) {
                            setState(() => _currentIndex++);
                          } else {
                            _submit(questions);
                          }
                        },
                        child: Text(
                          _currentIndex < questions.length - 1 ? 'Next' : 'Submit',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const LoadingList(),
        error: (e, st) => ErrorState(message: e.toString()),
      ),
    );
  }

  void _submit(List<Question> questions) {
    final results = <PracticeQuestionResult>[];
    for (var i = 0; i < questions.length; i++) {
      final selected = _selectedOptions[i];
      results.add(PracticeQuestionResult(
        question: questions[i],
        selectedOptionLabel: selected,
        isSkipped: selected == null,
      ));
    }
    final result = PracticeResult(
      phaseId: widget.phaseId,
      subjectId: widget.subjectId,
      results: results,
    );
    context.pushReplacement('/practice/result', extra: result);
  }
}
