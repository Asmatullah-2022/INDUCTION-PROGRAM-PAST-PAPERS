import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/paper_filter.dart';
import '../../core/validation/paper_status.dart';
import '../../data/models/paper.dart';
import '../../shared/widgets/state_widgets.dart';
import '../home/home_providers.dart';
import '../phases/phase_screen.dart' show subjectsProvider;
import 'admin_guard.dart';
import 'admin_providers.dart';

/// Admin paper list — unlike the normal SubjectScreen, this shows every
/// paper regardless of content_status, across all 24 phase/subject slots,
/// so admins can see at a glance which slots are Missing Source. Supports
/// search (title/cadre), phase/subject/status filters, and sorting —
/// entirely client-side (see PaperFilter) since the admin paper list is
/// at most 24 rows.
class AdminPapersScreen extends ConsumerStatefulWidget {
  const AdminPapersScreen({super.key});

  @override
  ConsumerState<AdminPapersScreen> createState() => _AdminPapersScreenState();
}

class _AdminPapersScreenState extends ConsumerState<AdminPapersScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _phaseId;
  String? _subjectId;
  String? _statusFilter;
  PaperSortOrder _sortOrder = PaperSortOrder.newest;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final papersAsync = ref.watch(adminAllPapersProvider);
    final phasesAsync = ref.watch(phasesProvider);
    final subjectsAsync = ref.watch(subjectsProvider);

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Manage Papers')),
        body: papersAsync.when(
          data: (papers) {
            final phaseNames = phasesAsync.maybeWhen(
              data: (phases) => {for (final p in phases) p.id: p.name},
              orElse: () => <String, String>{},
            );
            final subjectNames = subjectsAsync.maybeWhen(
              data: (subjects) => {for (final s in subjects) s.id: s.name},
              orElse: () => <String, String>{},
            );

            final filtered = PaperFilter.apply(
              papers: papers,
              query: _query,
              phaseId: _phaseId,
              subjectId: _subjectId,
              contentStatus: _statusFilter,
              sortOrder: _sortOrder,
            );

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search by title or cadre',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterDropdown<String?>(
                          label: 'Phase',
                          value: _phaseId,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Phases')),
                            ...phaseNames.entries
                                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                          ],
                          onChanged: (v) => setState(() => _phaseId = v),
                        ),
                        const SizedBox(width: 8),
                        _FilterDropdown<String?>(
                          label: 'Subject',
                          value: _subjectId,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Subjects')),
                            ...subjectNames.entries
                                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                          ],
                          onChanged: (v) => setState(() => _subjectId = v),
                        ),
                        const SizedBox(width: 8),
                        _FilterDropdown<String?>(
                          label: 'Status',
                          value: _statusFilter,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Statuses')),
                            ...PaperStatus.all.map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            ),
                          ],
                          onChanged: (v) => setState(() => _statusFilter = v),
                        ),
                        const SizedBox(width: 8),
                        _FilterDropdown<PaperSortOrder>(
                          label: 'Sort',
                          value: _sortOrder,
                          items: const [
                            DropdownMenuItem(value: PaperSortOrder.newest, child: Text('Newest')),
                            DropdownMenuItem(value: PaperSortOrder.oldest, child: Text('Oldest')),
                            DropdownMenuItem(value: PaperSortOrder.titleAsc, child: Text('Title')),
                          ],
                          onChanged: (v) => setState(() => _sortOrder = v ?? PaperSortOrder.newest),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: papers.isEmpty
                      ? const EmptyState(
                          icon: Icons.description_outlined,
                          title: 'No source papers imported.',
                          subtitle: 'Upload the original Phase II, Phase III or Phase IV '
                              'source paper to begin the verification workflow.',
                        )
                      : filtered.isEmpty
                          ? const EmptyState(
                              icon: Icons.search_off,
                              title: 'No papers match these filters',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: filtered.length + 1,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                if (index == 0) return const AdminMissingSlotsBanner();
                                final paper = filtered[index - 1];
                                return Card(
                                  child: ListTile(
                                    title: Text(
                                      '${phaseNames[paper.phaseId] ?? '?'} • '
                                      '${subjectNames[paper.subjectId] ?? '?'}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(paper.title),
                                    trailing: PaperStatusBadge(paper: paper),
                                    onTap: () => context.push('/admin/papers/${paper.id}'),
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
            onRetry: () => ref.invalidate(adminAllPapersProvider),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/admin/papers/new'),
          icon: const Icon(Icons.add),
          label: const Text('Import Source Paper'),
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(20),
        ),
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          hint: Text(label),
          underline: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class PaperStatusBadge extends StatelessWidget {
  final Paper paper;
  const PaperStatusBadge({super.key, required this.paper});

  @override
  Widget build(BuildContext context) {
    final presentation = PaperStatusPresentation.of(paper);
    final color = presentation.isMissingSource
        ? Colors.red
        : switch (paper.contentStatus) {
            'PUBLISHED' => Colors.green,
            'VERIFIED' => Colors.teal,
            'UNDER_REVIEW' => Colors.orange,
            'ARCHIVED' => Colors.grey,
            _ => Colors.blueGrey,
          };
    return Chip(
      label: Text(presentation.label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Shows the 24 expected phase/subject slots and highlights which ones
/// still have no paper at all, so admins can spot gaps without
/// cross-referencing the flat paper list mentally.
class AdminMissingSlotsBanner extends ConsumerWidget {
  const AdminMissingSlotsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final papersAsync = ref.watch(adminAllPapersProvider);
    return papersAsync.maybeWhen(
      data: (papers) {
        final filled = papers.map((p) => '${p.phaseId}::${p.subjectId}').toSet();
        final missing = AppConstants.totalExpectedPapers - filled.length;
        if (missing <= 0) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$missing of ${AppConstants.totalExpectedPapers} phase/subject slots have '
            'no paper yet — Missing Source.',
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
