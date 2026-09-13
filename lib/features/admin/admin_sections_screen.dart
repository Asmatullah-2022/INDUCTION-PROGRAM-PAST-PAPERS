import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';
import 'admin_providers.dart';

class AdminSectionsScreen extends ConsumerWidget {
  final String paperId;
  const AdminSectionsScreen({super.key, required this.paperId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(adminSectionsProvider(paperId));

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Sections')),
        body: sectionsAsync.when(
          data: (sections) {
            if (sections.isEmpty) {
              return const EmptyState(
                icon: Icons.view_list_outlined,
                title: 'No sections yet',
                subtitle: 'Add Section A / B / C matching the original paper\'s structure.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sections.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final section = sections[index];
                return Card(
                  child: ListTile(
                    title: Text(section.sectionName),
                    subtitle: Text(
                      'Code: ${section.sectionCode}'
                      '${section.marks != null ? " • ${section.marks} marks" : ""}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(context, ref, section.id),
                    ),
                    onTap: () => context
                        .push('/admin/papers/$paperId/sections/${section.id}/questions'),
                  ),
                );
              },
            );
          },
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(adminSectionsProvider(paperId)),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddSectionSheet(context, ref, sectionsAsync.value?.length ?? 0),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String sectionId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Section'),
        content: const Text(
          'This deletes the section and every question/option inside it. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(adminRepositoryProvider).deleteSection(sectionId);
              ref.invalidate(adminSectionsProvider(paperId));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddSectionSheet(BuildContext context, WidgetRef ref, int currentCount) {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final marksController = TextEditingController();
    final instructionsController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add Section', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Section Name (e.g. Section A)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: 'Section Code (e.g. A)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: marksController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Marks (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: instructionsController,
              decoration: const InputDecoration(labelText: 'Instructions (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty || codeController.text.trim().isEmpty) {
                  return;
                }
                await ref.read(adminRepositoryProvider).createSection(
                      paperId: paperId,
                      sectionName: nameController.text.trim(),
                      sectionCode: codeController.text.trim(),
                      marks: int.tryParse(marksController.text.trim()),
                      instructions: instructionsController.text.trim().isEmpty
                          ? null
                          : instructionsController.text.trim(),
                      displayOrder: currentCount,
                    );
                ref.invalidate(adminSectionsProvider(paperId));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Add Section'),
            ),
          ],
        ),
      ),
    );
  }
}
