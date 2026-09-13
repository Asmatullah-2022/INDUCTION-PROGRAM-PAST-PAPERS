import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/validation/paper_status.dart';
import '../../data/models/paper.dart';
import '../../shared/widgets/state_widgets.dart';
import '../papers/papers_providers.dart';
import 'admin_guard.dart';
import 'admin_papers_screen.dart' show PaperStatusBadge;
import 'admin_providers.dart';

/// The Paper Review screen: paper metadata, source document link,
/// section/question summary, and the quality report (score + errors +
/// warnings) that Verify/Publish are gated on. Every status action here
/// still only *proposes* the transition — admin_transition_paper_status
/// (006_admin_workflow.sql) is what actually enforces it server-side, so
/// this screen's gating is a UX convenience, not the security boundary.
class AdminPaperReviewScreen extends ConsumerStatefulWidget {
  final String paperId;
  const AdminPaperReviewScreen({super.key, required this.paperId});

  @override
  ConsumerState<AdminPaperReviewScreen> createState() => _AdminPaperReviewScreenState();
}

class _AdminPaperReviewScreenState extends ConsumerState<AdminPaperReviewScreen> {
  bool _isTransitioning = false;
  String? _error;

  Future<void> _transition(String newStatus) async {
    String? notes;
    if (newStatus == PaperStatus.verified || newStatus == PaperStatus.published) {
      final confirmed = await _confirm(newStatus);
      if (confirmed == null) return;
      notes = confirmed;
    }

    setState(() {
      _isTransitioning = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).transitionPaperStatus(
            paperId: widget.paperId,
            newStatus: newStatus,
            notes: notes,
          );
      ref.invalidate(paperByIdProvider(widget.paperId));
      ref.invalidate(adminAllPapersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Status updated to $newStatus.')));
      }
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not update status: $e');
    } finally {
      if (mounted) setState(() => _isTransitioning = false);
    }
  }

  Future<String?> _confirm(String newStatus) async {
    final controller = TextEditingController();
    final isPublish = newStatus == PaperStatus.published;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isPublish ? 'Publish this paper?' : 'Verify this paper?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isPublish
                ? 'This paper will become visible to all users. Only publish content '
                    'that has completed the verification workflow with zero critical '
                    'quality errors.'
                : 'Verifying records who verified this paper and when. Editing any '
                    'section or question afterward will automatically move it back to '
                    'Needs Review.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(isPublish ? 'Publish' : 'Verify'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paperAsync = ref.watch(paperByIdProvider(widget.paperId));
    final contentAsync = ref.watch(adminPaperContentProvider(widget.paperId));

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Review & Publish')),
        body: paperAsync.when(
          data: (paper) => contentAsync.when(
            data: (sections) => _buildBody(context, paper, sections),
            loading: () => const LoadingList(),
            error: (e, st) => ErrorState(message: e.toString()),
          ),
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(message: e.toString()),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Paper paper, List<SectionQuestions> sections) {
    final report = PaperQualityChecker.check(paper: paper, sections: sections);
    final totalQuestions = sections.fold<int>(0, (sum, s) => sum + s.questions.length);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(paper.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            PaperStatusBadge(paper: paper),
          ],
        ),
        const SizedBox(height: 4),
        Text('${sections.length} section(s) • $totalQuestions question(s)'),
        if (paper.verifiedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            'Verified ${paper.verifiedAt}${paper.verificationNotes != null ? " — ${paper.verificationNotes}" : ""}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        _QualityReportCard(report: report),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_error!),
          ),
        ],
        const SizedBox(height: 20),
        _buildActions(paper, report),
      ],
    );
  }

  Widget _buildActions(Paper paper, PaperQualityReport report) {
    final next = PaperStatusTransitions.allowedNextStatuses(paper.contentStatus);
    if (next.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: next.map((status) {
        final isBlocked = status == PaperStatus.verified || status == PaperStatus.published;
        final disabled = _isTransitioning || (isBlocked && report.hasCriticalErrors);
        return FilledButton(
          onPressed: disabled ? null : () => _transition(status),
          child: Text(_actionLabel(paper.contentStatus, status)),
        );
      }).toList(),
    );
  }

  String _actionLabel(String current, String next) {
    if (next == PaperStatus.underReview && current == PaperStatus.draft) return 'Submit for Review';
    if (next == PaperStatus.underReview) return 'Send Back to Review';
    if (next == PaperStatus.verified) return 'Verify';
    if (next == PaperStatus.published) return 'Publish';
    if (next == PaperStatus.archived) return 'Archive';
    if (next == PaperStatus.draft && current == PaperStatus.published) return 'Unpublish';
    if (next == PaperStatus.draft) return 'Restore to Draft';
    return next;
  }
}

class _QualityReportCard extends StatelessWidget {
  final PaperQualityReport report;
  const _QualityReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categoryColor = switch (report.category) {
      QualityCategory.pass => Colors.green,
      QualityCategory.warning => Colors.orange,
      QualityCategory.error => scheme.error,
    };
    final categoryLabel = switch (report.category) {
      QualityCategory.pass => 'PASS',
      QualityCategory.warning => 'WARNING',
      QualityCategory.error => 'ERROR',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('QUALITY CHECK',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const Spacer(),
                Chip(
                  label: Text('$categoryLabel — ${report.score}/100'),
                  backgroundColor: categoryColor.withValues(alpha: 0.12),
                  side: BorderSide(color: categoryColor.withValues(alpha: 0.4)),
                  labelStyle: TextStyle(color: categoryColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (report.errors.isEmpty && report.warnings.isEmpty)
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text('All checks passed.'),
                ],
              ),
            ...report.errors.map((e) => _IssueRow(issue: e, icon: Icons.cancel, color: scheme.error)),
            ...report.warnings
                .map((w) => _IssueRow(issue: w, icon: Icons.warning_amber_rounded, color: Colors.orange)),
          ],
        ),
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final QualityIssue issue;
  final IconData icon;
  final Color color;

  const _IssueRow({required this.issue, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(issue.message, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
