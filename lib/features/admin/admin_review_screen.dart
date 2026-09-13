import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/pagination/pagination_state.dart';
import '../../data/models/question.dart';
import '../../shared/widgets/quality_badge.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';
import 'admin_providers.dart';

/// Human-review queue (spec section 63): every question anywhere (draft or
/// published) whose quality_status isn't VERIFIED. AI must never
/// auto-publish these — an admin has to open each one, resolve or confirm
/// the note, and re-save it (which is also the only way to flip it back to
/// VERIFIED) before the paper it belongs to can be published.
///
/// Server-side keyset-paginated (docs/PERFORMANCE_AUDIT.md) — scrolling
/// near the bottom loads the next page instead of the screen ever loading
/// every questionable question in the database up front.
class AdminReviewScreen extends ConsumerStatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  ConsumerState<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends ConsumerState<AdminReviewScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(adminQuestionableQuestionsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminQuestionableQuestionsProvider);

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Review Questionable Questions')),
        body: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(PaginationState<Question> state) {
    if (state.isLoading) return const LoadingList();
    if (state.error != null && state.items.isEmpty) {
      return ErrorState(
        message: state.error!,
        onRetry: () => ref.read(adminQuestionableQuestionsProvider.notifier).refresh(),
      );
    }
    if (state.items.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Nothing to review',
        subtitle: 'Every question is currently marked VERIFIED.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(adminQuestionableQuestionsProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final q = state.items[index];
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
              onTap: () =>
                  context.push('/admin/review/sections/${q.paperSectionId}/questions/${q.id}'),
            ),
          );
        },
      ),
    );
  }
}
