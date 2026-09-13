import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/quality_badge.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';
import 'admin_providers.dart';

/// Human-review queue (spec section 63): every question anywhere (draft or
/// published) whose quality_status isn't VERIFIED. AI must never
/// auto-publish these — an admin has to open each one, resolve or confirm
/// the note, and re-save it (which is also the only way to flip it back to
/// VERIFIED) before the paper it belongs to can be published.
class AdminReviewScreen extends ConsumerWidget {
  const AdminReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(adminQuestionableQuestionsProvider);

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Review Questionable Questions')),
        body: questionsAsync.when(
          data: (questions) {
            if (questions.isEmpty) {
              return const EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Nothing to review',
                subtitle: 'Every question is currently marked VERIFIED.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: questions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final q = questions[index];
                return Card(
                  child: ListTile(
                    title: Text('Q${q.questionNumber}. ${q.questionText}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: QualityBadge(status: q.qualityStatus, note: q.qualityNote),
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context
                        .push('/admin/review/sections/${q.paperSectionId}/questions/${q.id}'),
                  ),
                );
              },
            );
          },
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(adminQuestionableQuestionsProvider),
          ),
        ),
      ),
    );
  }
}
