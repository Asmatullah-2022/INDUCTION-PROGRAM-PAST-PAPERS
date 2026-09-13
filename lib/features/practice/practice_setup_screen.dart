import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../home/home_providers.dart';
import '../phases/phase_screen.dart';

class PracticeSetupScreen extends ConsumerStatefulWidget {
  final String? initialPhaseId;
  final String? initialSubjectId;

  const PracticeSetupScreen({super.key, this.initialPhaseId, this.initialSubjectId});

  @override
  ConsumerState<PracticeSetupScreen> createState() => _PracticeSetupScreenState();
}

class _PracticeSetupScreenState extends ConsumerState<PracticeSetupScreen> {
  String? _phaseId;
  String? _subjectId;
  int? _questionCount = 20;

  @override
  void initState() {
    super.initState();
    _phaseId = widget.initialPhaseId;
    _subjectId = widget.initialSubjectId;
  }

  @override
  Widget build(BuildContext context) {
    final phasesAsync = ref.watch(phasesProvider);
    final subjectsAsync = ref.watch(subjectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Practice Setup')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phase', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            phasesAsync.when(
              data: (phases) => Wrap(
                spacing: 8,
                children: phases
                    .map((p) => ChoiceChip(
                          label: Text(p.name),
                          selected: _phaseId == p.id,
                          onSelected: (_) => setState(() => _phaseId = p.id),
                        ))
                    .toList(),
              ),
              loading: () => const SizedBox(
                  height: 32, child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, st) => Text('$e'),
            ),
            const SizedBox(height: 24),
            Text('Subject', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            subjectsAsync.when(
              data: (subjects) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subjects
                    .map((s) => ChoiceChip(
                          label: Text(s.name),
                          selected: _subjectId == s.id,
                          onSelected: (_) => setState(() => _subjectId = s.id),
                        ))
                    .toList(),
              ),
              loading: () => const SizedBox(
                  height: 32, child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, st) => Text('$e'),
            ),
            const SizedBox(height: 24),
            Text('Number of Questions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [10, 20, 30, 50, null].map((count) {
                return ChoiceChip(
                  label: Text(count == null ? 'All' : '$count'),
                  selected: _questionCount == count,
                  onSelected: (_) => setState(() => _questionCount = count),
                );
              }).toList(),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_phaseId != null && _subjectId != null)
                    ? () => context.push(
                          '/practice/session?phaseId=$_phaseId&subjectId=$_subjectId'
                          '${_questionCount != null ? "&limit=$_questionCount" : ""}',
                        )
                    : null,
                child: const Text('Start Practice'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
