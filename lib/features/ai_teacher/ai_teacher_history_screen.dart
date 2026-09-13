import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/ai_conversation.dart';
import '../../shared/widgets/state_widgets.dart';

final aiConversationsProvider = FutureProvider<List<AiConversation>>((ref) {
  return ref.read(aiTeacherRepositoryProvider).getConversations();
});

/// Lists the signed-in user's own AI Teacher conversations — RLS on
/// ai_conversations means this query can only ever return their own rows
/// (see 007_ai_teacher.sql), so conversation isolation between users is
/// enforced by the database, not by this screen filtering client-side.
class AiTeacherHistoryScreen extends ConsumerWidget {
  const AiTeacherHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(aiConversationsProvider);
    final formatter = DateFormat('MMM d, HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Conversation History')),
      body: conversationsAsync.when(
        data: (conversations) {
          if (conversations.isEmpty) {
            return const EmptyState(
              icon: Icons.history_outlined,
              title: 'No conversations yet',
              subtitle: 'Start a chat with AI Teacher to see it here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: conversations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatter.format(conversation.updatedAt)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(context, ref, conversation.id),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const LoadingList(),
        error: (e, st) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(aiConversationsProvider),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String conversationId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(aiTeacherRepositoryProvider).deleteConversation(conversationId);
              ref.invalidate(aiConversationsProvider);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
