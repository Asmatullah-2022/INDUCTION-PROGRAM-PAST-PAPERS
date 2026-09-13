import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/validation/ai_teacher_validation.dart';
import '../../data/models/ai_message.dart';
import 'ai_teacher_context.dart';

class _ChatEntry {
  final AiMessageRole role;
  final String content;
  final AiContentKind? contentKind;
  final bool isError;

  const _ChatEntry({
    required this.role,
    required this.content,
    this.contentKind,
    this.isError = false,
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

  Future<void> _send(AiTeacherAction action, {String? textOverride}) async {
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
    setState(() {
      if (text.isNotEmpty) {
        _entries.add(_ChatEntry(role: AiMessageRole.user, content: text));
      }
      _isSending = true;
      _lastFailedMessage = null;
      _lastFailedAction = null;
    });
    _inputController.clear();
    _scrollToBottom();

    final isOnline = await ref.read(connectivityServiceProvider).isOnline();
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

    try {
      final response = await ref.read(aiTeacherRepositoryProvider).sendMessage(
            action: action,
            message: text.isEmpty ? action.label : text,
            language: _language,
            conversationId: _conversationId,
            paperId: widget.context0?.paperId,
            questionId: widget.context0?.questionId,
          );
      setState(() {
        _conversationId = response.conversationId;
        _entries.add(_ChatEntry(
          role: AiMessageRole.assistant,
          content: response.assistantMessage.content,
          contentKind: response.assistantMessage.contentKind,
        ));
      });
    } on AppException catch (e) {
      setState(() {
        _entries.add(_ChatEntry(role: AiMessageRole.assistant, content: e.message, isError: true));
        _lastFailedMessage = text.isEmpty ? action.label : text;
        _lastFailedAction = action;
      });
    } catch (e) {
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
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  void _retry() {
    final message = _lastFailedMessage;
    final action = _lastFailedAction;
    if (message == null || action == null) return;
    setState(() => _entries.removeLast()); // drop the error bubble before retrying
    _send(action, textOverride: message);
  }

  void _clearChat() {
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
                case 'clear':
                  _clearChat();
                case 'copy':
                  _copyLast();
                case 'share':
                  _shareLast();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy last response')),
              PopupMenuItem(value: 'share', child: Text('Share last response')),
              PopupMenuItem(value: 'clear', child: Text('Clear chat / New conversation')),
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
                        onRetry: entry.isError && index == _entries.length - 1 ? _retry : null,
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
            enabled: !_isSending,
            onSend: () => _send(AiTeacherAction.ask),
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

  const _MessageBubble({required this.entry, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isUser = entry.role == AiMessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = entry.isError
        ? scheme.errorContainer
        : isUser
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow;
    final textColor = entry.isError
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
              const SizedBox(height: 4),
            ],
            Text(entry.content, style: TextStyle(color: textColor)),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
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
  final bool enabled;
  final VoidCallback onSend;

  const _InputBar({required this.controller, required this.enabled, required this.onSend});

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
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Ask AI Teacher...',
                  isDense: true,
                ),
                onSubmitted: enabled ? (_) => onSend() : null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
