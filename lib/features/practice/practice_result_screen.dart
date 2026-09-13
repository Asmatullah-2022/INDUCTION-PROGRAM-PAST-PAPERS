import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/question.dart';
import 'practice_result.dart';

String _correctLabel(Question question) {
  for (final option in question.options) {
    if (option.isVerifiedCorrect) return option.optionLabel;
  }
  return '-';
}

class PracticeResultScreen extends ConsumerStatefulWidget {
  final PracticeResult result;
  const PracticeResultScreen({super.key, required this.result});

  @override
  ConsumerState<PracticeResultScreen> createState() => _PracticeResultScreenState();
}

class _PracticeResultScreenState extends ConsumerState<PracticeResultScreen> {
  @override
  void initState() {
    super.initState();
    _persist();
  }

  Future<void> _persist() async {
    final r = widget.result;
    try {
      final attemptId = await ref.read(practiceRepositoryProvider).startAttempt(
            phaseId: r.phaseId,
            subjectId: r.subjectId,
            totalQuestions: r.total,
          );
      await ref.read(practiceRepositoryProvider).submitAttempt(
            attemptId: attemptId,
            answers: r.results
                .map((qr) => {
                      'question_id': qr.question.id,
                      'selected_option_label': qr.selectedOptionLabel,
                      'is_correct': qr.isCorrect,
                      'is_skipped': qr.isSkipped,
                    })
                .toList(),
            correctCount: r.correct,
            incorrectCount: r.incorrect,
            skippedCount: r.skipped,
          );
      await ref.read(progressRepositoryProvider).upsertProgress(
            phaseId: r.phaseId,
            subjectId: r.subjectId,
            attemptedDelta: r.total,
            correctDelta: r.correct,
            incorrectDelta: r.incorrect,
          );
    } catch (_) {
      // Best-effort: the score is still shown to the user even if syncing
      // the attempt to the server fails (e.g. offline).
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Scaffold(
      appBar: AppBar(title: const Text('Practice Result')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('${r.correct} / ${r.total}',
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text('${r.percentage.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _StatBox(label: 'Correct', value: r.correct, color: Colors.green)),
                const SizedBox(width: 12),
                Expanded(child: _StatBox(label: 'Incorrect', value: r.incorrect, color: Colors.red)),
                const SizedBox(width: 12),
                Expanded(child: _StatBox(label: 'Skipped', value: r.skipped, color: Colors.orange)),
              ],
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Review', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 12),
            ...r.results.asMap().entries.map((entry) {
              final index = entry.key;
              final qr = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            qr.isSkipped
                                ? Icons.remove_circle_outline
                                : qr.isCorrect
                                    ? Icons.check_circle
                                    : Icons.cancel,
                            color: qr.isSkipped
                                ? Colors.orange
                                : qr.isCorrect
                                    ? Colors.green
                                    : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Q${index + 1}. ${qr.question.questionText}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Your answer: ${qr.selectedOptionLabel ?? "Not answered"}'),
                      Text('Correct answer: ${_correctLabel(qr.question)}'),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
