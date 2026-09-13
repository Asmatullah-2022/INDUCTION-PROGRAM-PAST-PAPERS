import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/debouncer.dart';
import '../../data/repositories/search_repository.dart';
import '../../shared/widgets/state_widgets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _debouncer = Debouncer(delay: AppConstants.searchDebounce);
  static const _pageSize = 20;
  String _query = '';
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  List<SearchResultItem> _results = [];
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debouncer.run(() async {
      setState(() {
        _query = value;
        _isLoading = true;
        _error = null;
      });
      try {
        final page = await ref.read(searchRepositoryProvider).search(value, limit: _pageSize);
        if (mounted) {
          setState(() {
            _results = page.items;
            _hasMore = page.hasMore;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return; // no duplicate concurrent loads
    setState(() => _isLoadingMore = true);
    try {
      final page = await ref.read(searchRepositoryProvider).search(
            _query,
            offset: _results.length,
            limit: _pageSize,
          );
      if (mounted) {
        setState(() {
          _results = [..._results, ...page.items];
          _hasMore = page.hasMore;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search phases, subjects, questions...',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_query.trim().length < 2) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Search across all published content',
        subtitle: 'Type at least 2 characters to search phases, subjects, questions and answers.',
      );
    }
    if (_isLoading) return const LoadingList();
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: () => _onChanged(_query));
    }
    if (_results.isEmpty) {
      return const EmptyState(icon: Icons.search_off, title: 'No results found');
    }
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 200) _loadMore();
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _results.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _results.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = _results[index];
          return Card(
            child: ListTile(
              title: _highlightedText(item.question.questionText, _query),
              subtitle: Text('${item.phaseName} • ${item.subjectName}'),
            ),
          );
        },
      ),
    );
  }

  Widget _highlightedText(String text, String query) {
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final index = lower.indexOf(q);
    if (index < 0 || q.isEmpty) return Text(text);
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + q.length),
            style: const TextStyle(fontWeight: FontWeight.w800, backgroundColor: Color(0x33FFEB3B)),
          ),
          TextSpan(text: text.substring(index + q.length)),
        ],
      ),
    );
  }
}
