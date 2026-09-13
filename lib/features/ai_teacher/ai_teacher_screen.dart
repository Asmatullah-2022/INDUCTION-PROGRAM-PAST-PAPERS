import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/validation/ai_teacher_validation.dart';
import '../../data/models/ai_message.dart';
import '../../data/repositories/ai_teacher_repository.dart';
import 'ai_teacher_context.dart';

class _ChatEntry {
  final AiMessageRole role;
  final String content;
  final AiContentKind? contentKind;
  final bool isError;
  final bool isDiscrepancy;

  /// Only set on user entries — lets [_AiTeacherScreenState._regenerate]
  /// re-send the exact same action without the caller having to track it
  /// separately.
  final AiTeacherAction? action;

  const _ChatEntry({
    required this.role,
    required this.content,
    this.contentKind,
    this.isError = false,
    this.isDiscrepancy = false,
    this.action,
  });
}

/// The AI Teacher chat screen. Talks only to AiTeacherRepository (which
/// itself only ever calls the `ai-teacher` Edge Function) — never to an
/// AI provider directly, and holds no provider credentials. See
/// docs/AI_TEACHER_GUIDE.md.
class AiTeacherScreen extends ConsumerStatefulWidget {
  final AiTeacherContext? context0;

  const AiTeacherScreen({super.key, this.context0});

  @override
  ConsumerState<AiTeacherScreen> createState() => _AiTeacherScreenState();
}

class _AiTeacherScreenState extends ConsumerState<AiTeacherScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatEntry> _entries = [];
  String? _conversationId;
  String _language = 'en';
  bool _isSending = false;
  String? _lastFailedMessage;
  AiTeacherAction? _lastFailedAction;

  /// Bumped on every new send and on Stop, so a superseded/cancelled
  /// request's `finally` block can tell it's no longer the active one and
  /// avoid clobbering a later request's loading state.
  int _generation = 0;
  CancelableOperation<AiTeacherResponse>? _activeOperation;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasQuestionContext => widget.context0?.hasQuestion ?? false;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(
    AiTeacherAction action, {
    String? textOverride,
    bool appendUserEntry = true,
  }) async {
    final text = (textOverride ?? _inputController.text).trim();
    // A quick-action tap with no free-text override sends the action's
    // own label as the message (e.g. "Exam Tip"); only the free-text
    // "Ask" send button requires the user to have typed something.
    if (text.isEmpty && action == AiTeacherAction.ask) {
      setState(() => _entries.add(const _ChatEntry(
            role: AiMessageRole.assistant,
            content: 'Please enter a message.',
            isError: true,
          )));
      _scrollToBottom();
      return;
    }

    // Set the pending state and the user's own bubble synchronously,
    // before any await, so the UI gives immediate feedback on tap rather
    // than waiting on the connectivity check first.
    final generation = ++_generation;
    setState(() {
      if (appendUserEntry && text.isNotEmpty) {
        _entries.add(_ChatEntry(role: AiMessageRole.user, content: text, action: action));
      }
      _isSending = true;
      _lastFailedMessage = null;
      _lastFailedAction = null;
    });
    _inputController.clear();
    _scrollToBottom();

    final isOnline = await ref.read(connectivityServiceProvider).isOnline();
    if (generation != _generation) return; // stopped/superseded while checking connectivity
    if (!isOnline) {
      setState(() {
        _isSending = false;
        _entries.add(const _ChatEntry(
          role: AiMessageRole.assistant,
          content: "You're offline. AI Teacher needs an internet connection.",
          isError: true,
        ));
      });
      _scrollToBottom();
      return;
    }

    // Wrapped in CancelableOperation so Stop Generation has something
    // concrete to cancel — see _stopGeneration for what this can and
    // cannot actually stop.
    final operation = CancelableOperation<AiTeacherResponse>.fromFuture(
      ref.read(aiTeacherRepositoryProvider).sendMessage(
            action: action,
            message: text.isEmpty ? action.label : text,
            language: _language,
            conversationId: _conversationId,
            paperId: widget.context0?.paperId,
            questionId: widget.context0?.questionId,
          ),
    );
    _activeOperation = operation;

    try {
      final response = await operation.valueOrCancellation();
      if (response == null) return; // cancelled by _stopGeneration
      if (generation != _generation) return;
      setState(() {
        _conversationId = response.conversationId;
        _entries.add(_ChatEntry(
          role: AiMessageRole.assistant,
          content: response.assistantMessage.content,
          contentKind: response.assistantMessage.contentKind,
        ));
        _appendDiscrepancyNoticeIfAny(response.assistantMessage);
      });
    } on AppException catch (e) {
      if (generation != _generation) return;
      setState(() {
        _entries.add(_ChatEntry(role: AiMessageRole.assistant, content: e.message, isError: true));
        _lastFailedMessage = text.isEmpty ? action.label : text;
        _lastFailedAction = action;
      });
    } catch (e) {
      if (generation != _generation) return;
      setState(() {
        _entries.add(const _ChatEntry(
          role: AiMessageRole.assistant,
          content: 'AI Teacher is temporarily unavailable. Please try again.',
          isError: true,
        ));
        _lastFailedMessage = text.isEmpty ? action.label : text;
        _lastFailedAction = action;
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  /// Client-side half of the "verified content has priority" rule — see
  /// AiDiscrepancyDetector's doc comment. Only checked for a question
  /// opened in MCQ context where the app itself holds a verified answer.
  void _appendDiscrepancyNoticeIfAny(AiMessage assistantMessage) {
    final verifiedAnswer = widget.context0?.verifiedAnswer;
    if (widget.context0?.isMcq != true || verifiedAnswer == null) return;
    if (!AiDiscrepancyDetector.hasDiscrepancy(assistantMessage.content, verifiedAnswer)) return;
    _entries.add(const _ChatEntry(
      role: AiMessageRole.assistant,
      content: 'Potential discrepancy detected. The stored answer is marked VERIFIED. '
          'Please refer to the source paper or administrator verification.',
      isDiscrepancy: true,
    ));
  }

  /// Stops waiting on the in-flight request. The Supabase functions
  /// client has no cancellation hook, so the actual HTTP call to the
  /// Edge Function (and the provider call behind it) is NOT aborted —
  /// this only stops the UI from waiting for or displaying its result,
  /// which is the safest client-side cancellation available with this
  /// transport. See docs/AI_TEACHER_GUIDE.md "Stop Generation".
  void _stopGeneration() {
    if (!_isSending) return;
    _generation++; // invalidate the in-flight request before it resolves
    _activeOperation?.cancel();
    setState(() {
      _isSending = false;
      _entries.add(const _ChatEntry(
        role: AiMessageRole.assistant,
        content: 'Generation stopped.',
        isError: true,
      ));
    });
    _scrollToBottom();
  }

  void _retry() {
    final message = _lastFailedMessage;
    final action = _lastFailedAction;
    if (message == null || action == null) return;
    setState(() => _entries.removeLast()); // drop the error bubble before retrying
    _send(action, textOverride: message, appendUserEntry: false);
  }

  void _regenerate() {
    _ChatEntry? lastUser;
    for (final entry in _entries.reversed) {
      if (entry.role == AiMessageRole.user) {
        lastUser = entry;
        break;
      }
    }
    if (lastUser == null || lastUser.action == null) return;
    setState(() {
      // Drop the trailing assistant reply (and any discrepancy notice)
      // so the regenerated answer replaces it, without touching the
      // user's own message or re-sending it as a duplicate bubble.
      while (_entries.isNotEmpty && _entries.last.role == AiMessageRole.assistant) {
        _entries.removeLast();
      }
    });
    _send(lastUser.action!, textOverride: lastUser.content, appendUserEntry: false);
  }

  /// Starts a fresh conversation. The previous conversation is not
  /// deleted — it stays reachable from Conversation History, because its
  /// messages are already persisted server-side under their own
  /// conversationId. This only resets local view state.
  void _newConversation() {
    setState(() {
      _entries.clear();
      _conversationId = null;
      _lastFailedMessage = null;
      _lastFailedAction = null;
    });
  }

  /// Destructively clears the current conversation after confirmation —
  /// unlike New Conversation, this deletes the underlying conversation
  /// (if one has been created) so it no longer appears in history either.
  Future<void> _confirmClearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text('This removes the current conversation and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final conversationId = _conversationId;
    if (conversationId != null) {
      await ref.read(aiTeacherRepositoryProvider).deleteConversation(conversationId);
    }
    if (!mounted) return;
    setState(() {
      _entries.clear();
      _conversationId = null;
      _lastFailedMessage = null;
      _lastFailedAction = null;
    });
  }

  void _copyLast() {
    final lastAssistant = _entries.reversed.where((e) => e.role == AiMessageRole.assistant).firstOrNull;
    if (lastAssistant == null) return;
    Clipboard.setData(ClipboardData(text: lastAssistant.content));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard.')));
  }

  void _shareLast() {
    final lastAssistant = _entries.reversed.where((e) => e.role == AiMessageRole.assistant).firstOrNull;
    if (lastAssistant == null) return;
    Share.share(lastAssistant.content);
  }

  @override
  Widget build(BuildContext context) {
    final actions = _hasQuestionContext
        ? AiTeacherActionX.questionContextActions
        : AiTeacherActionX.generalActions;
    final lastAssistantIndex =
        _entries.lastIndexWhere((e) => e.role == AiMessageRole.assistant && !e.isError);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Teacher'),
        actions: [
          IconButton(
            icon: Icon(_language == 'ur' ? Icons.translate : Icons.language),
            tooltip: 'Toggle language',
            onPressed: () => setState(() => _language = _language == 'ur' ? 'en' : 'ur'),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Conversation History',
            onPressed: () => context.push('/ai-teacher/history'),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'new_conversation':
                  _newConversation();
                case 'clear_chat':
                  _confirmClearChat();
                case 'copy':
                  _copyLast();
                case 'share':
                  _shareLast();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy last response')),
              PopupMenuItem(value: 'share', child: Text('Share last response')),
              PopupMenuItem(value: 'new_conversation', child: Text('New Conversation')),
              PopupMenuItem(value: 'clear_chat', child: Text('Clear Chat')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.context0?.questionPreview != null) _QuestionContextBanner(context0: widget.context0!),
          Expanded(
            child: _entries.isEmpty
                ? _EmptyState(hasQuestionContext: _hasQuestionContext)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length + (_isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _entries.length) {
                        return const _LoadingBubble();
                      }
                      final entry = _entries[index];
                      return _MessageBubble(
                        entry: entry,
                        onRetry: entry.isError && !_isSending && index == _entries.length - 1 ? _retry : null,
                        onRegenerate: !_isSending && index == lastAssistantIndex ? _regenerate : null,
                      );
                    },
                  ),
          ),
          _QuickActionsRow(
            actions: actions,
            enabled: !_isSending,
            onTap: (action) => _send(action, textOverride: _hasQuestionContext ? action.label : null),
          ),
          _InputBar(
            controller: _inputController,
            isSending: _isSending,
            onSend: () => _send(AiTeacherAction.ask),
            onStop: _stopGeneration,
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _QuestionContextBanner extends StatelessWidget {
  final AiTeacherContext context0;
  const _QuestionContextBanner({required this.context0});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: scheme.secondaryContainer,
      child: Row(
        children: [
          Icon(Icons.quiz_outlined, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context0.questionPreview!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasQuestionContext;
  const _EmptyState({required this.hasQuestionContext});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'AI Teacher',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Learn • Understand • Practice', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text(
              hasQuestionContext
                  ? 'Pick a quick action below, or ask your own question about this question.'
                  : 'Ask about any educational topic, or use a quick action below.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBubble extends StatelessWidget {
  const _LoadingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatEntry entry;
  final VoidCallback? onRetry;
  final VoidCallback? onRegenerate;

  const _MessageBubble({required this.entry, this.onRetry, this.onRegenerate});

  @override
  Widget build(BuildContext context) {
    final isUser = entry.role == AiMessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    final flagged = entry.isError || entry.isDiscrepancy;
    final bubbleColor = flagged
        ? scheme.errorContainer
        : isUser
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow;
    final textColor = flagged
        ? scheme.onErrorContainer
        : isUser
            ? scheme.onPrimaryContainer
            : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && entry.contentKind != null && !entry.isError) ...[
              Text(
                entry.contentKind!.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: entry.contentKind!.isBasedOnVerifiedContent
                      ? Colors.teal
                      : Colors.orange.shade800,
                ),
              ),
              if (entry.contentKind!.needsReviewBadge)
                Text(
                  'NEEDS REVIEW',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.error),
                ),
              const SizedBox(height: 4),
            ],
            entry.isError || entry.isDiscrepancy
                ? Text(entry.content, style: TextStyle(color: textColor))
                : _MarkdownLiteText(text: entry.content, style: TextStyle(color: textColor)),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
            if (onRegenerate != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.autorenew, size: 16),
                label: const Text('Regenerate'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A deliberately small markdown-lite renderer — headings (`### `),
/// bullet lists (`- `/`* `), numbered lists (`1. `), and inline `**bold**`
/// — covering what AI Teacher responses actually use, without pulling in
/// a full markdown package. Not a general-purpose renderer: no tables,
/// links, or code fences. See docs/AI_TEACHER_GUIDE.md.
class _MarkdownLiteText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _MarkdownLiteText({required this.text, this.style});

  static final _bulletPattern = RegExp(r'^[-*]\s+(.*)');
  static final _numberedPattern = RegExp(r'^(\d+)\.\s+(.*)');

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        if (line.trim().isEmpty) return const SizedBox(height: 6);

        if (line.startsWith('### ')) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              line.substring(4),
              style: (style ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          );
        }

        final bulletMatch = _bulletPattern.firstMatch(line);
        if (bulletMatch != null) {
          return Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: style),
                Expanded(child: _InlineBoldText(text: bulletMatch.group(1)!, style: style)),
              ],
            ),
          );
        }

        final numberedMatch = _numberedPattern.firstMatch(line);
        if (numberedMatch != null) {
          return Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${numberedMatch.group(1)}.  ', style: style),
                Expanded(child: _InlineBoldText(text: numberedMatch.group(2)!, style: style)),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _InlineBoldText(text: line, style: style),
        );
      }).toList(),
    );
  }
}

class _InlineBoldText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _InlineBoldText({required this.text, this.style});

  static final _boldPattern = RegExp(r'\*\*(.+?)\*\*');

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _boldPattern.allMatches(text)) {
      if (match.start > last) spans.add(TextSpan(text: text.substring(last, match.start)));
      spans.add(TextSpan(text: match.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    // Text.rich (not a bare RichText) so widget/integration tests using
    // find.text() — which only inspects Text widgets — can still find
    // this content, matching against the span tree's plain text.
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _QuickActionsRow extends StatelessWidget {
  final List<AiTeacherAction> actions;
  final bool enabled;
  final ValueChanged<AiTeacherAction> onTap;

  const _QuickActionsRow({required this.actions, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionChip(
            label: Text(action.label),
            onPressed: enabled ? () => onTap(action) : null,
          );
        },
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const _InputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !isSending,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Ask AI Teacher...',
                  isDense: true,
                ),
                onSubmitted: isSending ? null : (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            isSending
                ? IconButton.filled(
                    onPressed: onStop,
                    tooltip: 'Stop generation',
                    icon: const Icon(Icons.stop),
                  )
                : IconButton.filled(
                    onPressed: onSend,
                    icon: const Icon(Icons.send),
                  ),
          ],
        ),
      ),
    );
  }
}
