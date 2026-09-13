import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/bookmark.dart';
import '../../shared/widgets/state_widgets.dart';

final myBookmarksProvider =
    FutureProvider.family<List<Bookmark>, BookmarkTargetType?>((ref, type) {
  return ref.read(bookmarkRepositoryProvider).getMyBookmarks(type: type);
});

class BookmarksScreen extends ConsumerStatefulWidget {
  const BookmarksScreen({super.key});

  @override
  ConsumerState<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends ConsumerState<BookmarksScreen> {
  BookmarkTargetType? _filter;

  @override
  Widget build(BuildContext context) {
    final bookmarksAsync = ref.watch(myBookmarksProvider(_filter));

    return Scaffold(
      appBar: AppBar(title: const Text('My Bookmarks')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                _FilterChip(label: 'All', selected: _filter == null,
                    onTap: () => setState(() => _filter = null)),
                _FilterChip(
                    label: 'MCQs',
                    selected: _filter == BookmarkTargetType.mcq,
                    onTap: () => setState(() => _filter = BookmarkTargetType.mcq)),
                _FilterChip(
                    label: 'Short Questions',
                    selected: _filter == BookmarkTargetType.short,
                    onTap: () => setState(() => _filter = BookmarkTargetType.short)),
                _FilterChip(
                    label: 'Long Questions',
                    selected: _filter == BookmarkTargetType.long,
                    onTap: () => setState(() => _filter = BookmarkTargetType.long)),
                _FilterChip(
                    label: 'Papers',
                    selected: _filter == BookmarkTargetType.paper,
                    onTap: () => setState(() => _filter = BookmarkTargetType.paper)),
              ],
            ),
          ),
          Expanded(
            child: bookmarksAsync.when(
              data: (bookmarks) {
                if (bookmarks.isEmpty) {
                  return const EmptyState(
                    icon: Icons.bookmark_outline,
                    title: 'No bookmarks yet',
                    subtitle: 'Bookmark questions and papers while studying to find them here.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: bookmarks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final b = bookmarks[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(_iconFor(b.targetType)),
                        title: Text(_labelFor(b.targetType)),
                        subtitle: Text('Saved ${_timeAgo(b.createdAt)}'),
                      ),
                    );
                  },
                );
              },
              loading: () => const LoadingList(),
              error: (e, st) => ErrorState(
                message: e.toString(),
                onRetry: () => ref.invalidate(myBookmarksProvider(_filter)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(BookmarkTargetType type) => switch (type) {
        BookmarkTargetType.paper => Icons.description_outlined,
        BookmarkTargetType.mcq => Icons.quiz_outlined,
        BookmarkTargetType.short => Icons.short_text_outlined,
        BookmarkTargetType.long => Icons.notes_outlined,
      };

  String _labelFor(BookmarkTargetType type) => switch (type) {
        BookmarkTargetType.paper => 'Paper',
        BookmarkTargetType.mcq => 'MCQ',
        BookmarkTargetType.short => 'Short Question',
        BookmarkTargetType.long => 'Long Question',
      };

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}
