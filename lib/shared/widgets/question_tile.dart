import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/bookmark.dart';
import '../../data/models/question.dart';
import '../../features/ai_teacher/ai_teacher_context.dart';
import 'quality_badge.dart';

/// Renders one question (MCQ/short/long) with its verified answer,
/// explanation, and quality-check badge. Used by the answer key, short
/// answers, long answers, and complete-solution screens.
class QuestionTile extends ConsumerWidget {
  final Question question;
  final bool showBookmark;

  /// When supplied, an "Ask AI Teacher about this question" button is
  /// shown, opening the chat pre-loaded with this question's verified
  /// content as context (see AiTeacherContext).
  final String? paperId;

  const QuestionTile({
    super.key,
    required this.question,
    this.showBookmark = true,
    this.paperId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Q${question.questionNumber}. ${question.questionText}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                if (showBookmark)
                  IconButton(
                    icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                    onPressed: () => ref.read(bookmarkRepositoryProvider).toggleBookmark(
                          type: _bookmarkType(question.questionType),
                          targetId: question.id,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            QualityBadge(status: question.qualityStatus, note: question.qualityNote),
            const SizedBox(height: 12),
            if (question.options.isNotEmpty)
              ...question.options.map((o) {
                final isVerifiedCorrect = o.isVerifiedCorrect;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: isVerifiedCorrect
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Text(
                          o.optionLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: isVerifiedCorrect
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          o.optionText,
                          style: TextStyle(
                            fontWeight: isVerifiedCorrect ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (question.hasAnswerKeyDiscrepancy) ...[
              const SizedBox(height: 8),
              _DiscrepancyNotice(question: question),
            ],
            if (question.questionType.name != 'mcq' && question.verifiedAnswer != null) ...[
              const SizedBox(height: 8),
              Text(
                question.verifiedAnswer!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (question.explanation != null && question.explanation!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Explanation',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(question.explanation!),
                  ],
                ),
              ),
            ],
            if (paperId != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(
                    '/ai-teacher',
                    extra: AiTeacherContext(
                      paperId: paperId,
                      questionId: question.id,
                      questionPreview: question.questionText,
                      isMcq: question.questionType.name == 'mcq',
                    ),
                  ),
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: const Text('Ask AI Teacher'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  BookmarkTargetType _bookmarkType(dynamic questionType) {
    final name = questionType.toString().split('.').last;
    switch (name) {
      case 'mcq':
        return BookmarkTargetType.mcq;
      case 'short':
        return BookmarkTargetType.short;
      default:
        return BookmarkTargetType.long;
    }
  }
}

class _DiscrepancyNotice extends StatelessWidget {
  final Question question;
  const _DiscrepancyNotice({required this.question});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⚠ Answer key requires review',
              style: TextStyle(fontWeight: FontWeight.w700, color: scheme.error)),
          const SizedBox(height: 4),
          Text('Original marked answer: ${question.originalMarkedOption ?? '-'}'),
          Text('Verified answer: ${question.verifiedAnswer ?? '-'}'),
        ],
      ),
    );
  }
}
