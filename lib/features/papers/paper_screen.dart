import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/state_widgets.dart';
import 'papers_providers.dart';

class PaperScreen extends ConsumerWidget {
  final String paperId;
  const PaperScreen({super.key, required this.paperId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paperAsync = ref.watch(paperByIdProvider(paperId));
    final sectionsAsync = ref.watch(paperSectionsProvider(paperId));

    return Scaffold(
      appBar: AppBar(
        title: paperAsync.maybeWhen(
          data: (p) => Text(p.title),
          orElse: () => const Text('Paper'),
        ),
      ),
      body: paperAsync.when(
        data: (paper) {
          final totalQuestions = sectionsAsync.maybeWhen(
            data: (sections) =>
                sections.fold<int>(0, (sum, s) => sum + s.questions.length),
            orElse: () => null,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (paper.totalMarks != null)
                        _InfoChip(label: 'Total Marks', value: '${paper.totalMarks}'),
                      if (paper.durationMinutes != null)
                        _InfoChip(label: 'Duration', value: '${paper.durationMinutes} min'),
                      if (totalQuestions != null)
                        _InfoChip(label: 'Questions', value: '$totalQuestions'),
                      _InfoChip(
                        label: 'Status',
                        value: paper.verificationStatus,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _MenuTile(
                icon: Icons.picture_as_pdf_outlined,
                title: 'Original Paper',
                subtitle: 'View the scanned/source paper exactly as supplied',
                onTap: () => context.push('/paper/$paperId/original'),
              ),
              _MenuTile(
                icon: Icons.fact_check_outlined,
                title: 'MCQ Answer Key',
                subtitle: 'All MCQs with verified answers and explanations',
                onTap: () => context.push('/paper/$paperId/answer-key'),
              ),
              _MenuTile(
                icon: Icons.short_text_outlined,
                title: 'Short Questions & Answers',
                subtitle: 'Section B — concise exam-style answers',
                onTap: () => context.push('/paper/$paperId/short-answers'),
              ),
              _MenuTile(
                icon: Icons.notes_outlined,
                title: 'Long Questions & Answers',
                subtitle: 'Section C — detailed exam-style answers',
                onTap: () => context.push('/paper/$paperId/long-answers'),
              ),
              _MenuTile(
                icon: Icons.menu_book_outlined,
                title: 'Complete Solved Paper',
                subtitle: 'Full paper with every answer and explanation',
                onTap: () => context.push('/paper/$paperId/complete-solution'),
              ),
            ],
          );
        },
        loading: () => const LoadingList(itemCount: 5),
        error: (e, st) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(paperByIdProvider(paperId)),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
