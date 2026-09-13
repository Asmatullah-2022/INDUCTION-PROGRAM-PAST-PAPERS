import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/question_reorder.dart';
import '../../core/validation/question_numbering.dart';
import '../../data/models/question.dart';
import '../../shared/widgets/quality_badge.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';
import 'admin_providers.dart';

/// The Section Editor: lists a section's questions in order, with
/// drag-to-reorder (auto-renumbering sequentially on drop, per
/// CLAUDE.md), live duplicate/gap detection via QuestionNumberingValidator
/// (the same rule PaperQualityChecker uses at the paper level — never
/// re-implemented here), unsaved-changes tracking, save/cancel, and a
/// single-level undo of the last move.
class AdminQuestionsScreen extends ConsumerStatefulWidget {
  final String paperId;
  final String sectionId;
  const AdminQuestionsScreen({super.key, required this.paperId, required this.sectionId});

  @override
  ConsumerState<AdminQuestionsScreen> createState() => _AdminQuestionsScreenState();
}

class _AdminQuestionsScreenState extends ConsumerState<AdminQuestionsScreen> {
  List<Question>? _workingList;
  final List<List<Question>> _undoStack = [];
  bool _isDirty = false;
  bool _isSaving = false;

  void _syncFromServer(List<Question> serverQuestions) {
    if (_isDirty) return; // never clobber an in-progress reorder
    setState(() {
      _workingList = List.of(serverQuestions)
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      _undoStack.clear();
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    final list = _workingList;
    if (list == null) return;
    // ReorderableListView's newIndex is measured before the dragged item
    // is removed — adjust when moving downward so it lands where it looks.
    if (oldIndex < newIndex) newIndex -= 1;
    setState(() {
      _undoStack.add(List.of(list));
      _workingList = QuestionReorder.moveAndRenumber(
        questions: list,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
      _isDirty = true;
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      // Each stack entry is a snapshot taken right before a move. Popping
      // one restores the state before that move; an empty stack afterward
      // means every move has been undone, back to the last saved state.
      _workingList = _undoStack.removeLast();
      _isDirty = _undoStack.isNotEmpty;
    });
  }

  void _cancel(List<Question> serverQuestions) {
    setState(() {
      _workingList = List.of(serverQuestions)
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      _undoStack.clear();
      _isDirty = false;
    });
  }

  Future<void> _save() async {
    final list = _workingList;
    if (list == null) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(adminRepositoryProvider).reorderQuestions(list);
      ref.invalidate(adminQuestionsProvider(widget.sectionId));
      if (mounted) {
        setState(() {
          _isDirty = false;
          _undoStack.clear();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Question order saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save order: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(adminQuestionsProvider(widget.sectionId));

    ref.listen(adminQuestionsProvider(widget.sectionId), (previous, next) {
      next.whenData(_syncFromServer);
    });

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Section Editor'),
          actions: [
            if (_undoStack.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Undo last move',
                onPressed: _isSaving ? null : _undo,
              ),
          ],
        ),
        body: questionsAsync.when(
          data: (serverQuestions) {
            _workingList ??= List.of(serverQuestions)
              ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
            final list = _workingList!;

            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.quiz_outlined,
                title: 'No questions in this section yet',
              );
            }

            final report =
                QuestionNumberingValidator.check(list.map((q) => q.questionNumber).toList());

            return Column(
              children: [
                _NumberingStatusBanner(report: report),
                if (_isDirty) _UnsavedChangesBar(
                  isSaving: _isSaving,
                  onSave: _save,
                  onCancel: () => _cancel(serverQuestions),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: list.length,
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final question = list[index];
                      return _QuestionCard(
                        key: ValueKey(question.id),
                        index: index,
                        question: question,
                        disabled: _isSaving,
                        onDelete: _isDirty
                            ? null
                            : () => _confirmDelete(context, question.id),
                        onTap: _isDirty
                            ? null
                            : () => context.push(
                                  '/admin/papers/${widget.paperId}/sections/${widget.sectionId}/questions/${question.id}',
                                ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(adminQuestionsProvider(widget.sectionId)),
          ),
        ),
        floatingActionButton: _isDirty
            ? null
            : FloatingActionButton(
                onPressed: () => context.push(
                  '/admin/papers/${widget.paperId}/sections/${widget.sectionId}/questions/new',
                ),
                child: const Icon(Icons.add),
              ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String questionId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Question'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(adminRepositoryProvider).deleteQuestion(questionId);
              ref.invalidate(adminQuestionsProvider(widget.sectionId));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _NumberingStatusBanner extends StatelessWidget {
  final QuestionNumberingReport report;
  const _NumberingStatusBanner({required this.report});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final String text;
    late final Color color;
    late final IconData icon;

    if (report.isValid) {
      text = 'Numbering valid';
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (report.hasErrors) {
      text = '${report.errors.length} numbering error(s)';
      color = scheme.error;
      icon = Icons.cancel;
    } else {
      text = '${report.warnings.length} numbering issue(s)';
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          if (!report.isValid)
            IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: () => _showIssues(context),
            ),
        ],
      ),
    );
  }

  void _showIssues(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Numbering Issues', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...report.errors.map((i) => _issueRow(context, i.message, isError: true)),
            ...report.warnings.map((i) => _issueRow(context, i.message, isError: false)),
          ],
        ),
      ),
    );
  }

  Widget _issueRow(BuildContext context, String message, {required bool isError}) {
    final color = isError ? Theme.of(context).colorScheme.error : Colors.orange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(isError ? Icons.cancel : Icons.warning_amber_rounded, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class _UnsavedChangesBar extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _UnsavedChangesBar({
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Row(
        children: [
          Icon(Icons.edit_note, size: 18, color: Theme.of(context).colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Unsaved changes — order not yet saved',
              style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer),
            ),
          ),
          TextButton(onPressed: isSaving ? null : onCancel, child: const Text('Cancel')),
          FilledButton(
            onPressed: isSaving ? null : onSave,
            child: isSaving
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Order'),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final int index;
  final Question question;
  final bool disabled;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const _QuestionCard({
    super.key,
    required this.index,
    required this.question,
    required this.disabled,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Text('Q${question.questionNumber} — ${question.questionType.dbValue.toUpperCase()}'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question.questionText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              QualityBadge(status: question.qualityStatus, note: question.qualityNote),
            ],
          ),
        ),
        trailing: onDelete == null
            ? null
            : IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
        onTap: onTap,
      ),
    );
  }
}
