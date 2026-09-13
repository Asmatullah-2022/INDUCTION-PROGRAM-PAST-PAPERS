import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/paper.dart';
import '../../shared/widgets/state_widgets.dart';
import '../home/home_providers.dart';
import '../papers/papers_providers.dart';
import '../phases/phase_screen.dart' show subjectsProvider;
import 'admin_guard.dart';
import 'admin_providers.dart';

const _contentStatuses = ['DRAFT', 'UNDER_REVIEW', 'VERIFIED', 'PUBLISHED', 'ARCHIVED'];

class AdminPaperDetailScreen extends ConsumerStatefulWidget {
  final String paperId;
  const AdminPaperDetailScreen({super.key, required this.paperId});

  @override
  ConsumerState<AdminPaperDetailScreen> createState() => _AdminPaperDetailScreenState();
}

class _AdminPaperDetailScreenState extends ConsumerState<AdminPaperDetailScreen> {
  bool _isUploading = false;
  String? _statusError;

  Future<void> _pickAndUploadFile(Paper paper) async {
    final phases = await ref.read(phasesProvider.future);
    final subjects = await ref.read(subjectsProvider.future);
    final phase = phases.where((p) => p.id == paper.phaseId).firstOrNull;
    final subject = subjects.where((s) => s.id == paper.subjectId).firstOrNull;
    if (phase == null || subject == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;
    final extension = (file.extension ?? 'pdf').toLowerCase();

    setState(() => _isUploading = true);
    try {
      await ref.read(adminRepositoryProvider).uploadOriginalPaperFile(
            paperId: paper.id,
            phaseSlug: phase.slug,
            subjectSlug: subject.slug,
            bytes: bytes,
            extension: extension,
          );
      ref.invalidate(paperByIdProvider(paper.id));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Original paper file uploaded.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _changeStatus(Paper paper, String newStatus) async {
    // Publishing must always be an explicit, informed decision — never a
    // one-tap accident — so confirm before flipping to PUBLISHED.
    if (newStatus == 'PUBLISHED') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Publish this paper?'),
          content: const Text(
            'This paper will become visible to all users. Only publish content '
            'that has completed the verification workflow (no unresolved '
            'QUESTIONABLE / PAPER_ERROR / OCR_UNCERTAIN / ANSWER_UNCERTAIN items).',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Publish')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await ref
          .read(adminRepositoryProvider)
          .setContentStatus(paperId: paper.id, status: newStatus);
      ref.invalidate(adminAllPapersProvider);
      ref.invalidate(paperByIdProvider(paper.id));
    } catch (e) {
      setState(() => _statusError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final paperAsync = ref.watch(paperByIdProvider(widget.paperId));
    final sectionsAsync = ref.watch(adminSectionsProvider(widget.paperId));

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Paper')),
        body: paperAsync.when(
          data: (paper) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(paper.title,
                  style:
                      Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Content Status', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _contentStatuses
                            .map((status) => ChoiceChip(
                                  label: Text(status),
                                  selected: paper.contentStatus == status,
                                  onSelected: (_) => _changeStatus(paper, status),
                                ))
                            .toList(),
                      ),
                      if (_statusError != null) ...[
                        const SizedBox(height: 8),
                        Text(_statusError!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Original Paper File', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 8),
                      Text(paper.sourceFileUrl == null
                          ? 'MISSING SOURCE PAPER — DO NOT PUBLISH'
                          : 'Uploaded (${paper.sourceFileType ?? "unknown type"})'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isUploading ? null : () => _pickAndUploadFile(paper),
                        icon: _isUploading
                            ? const SizedBox(
                                height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file_outlined),
                        label: Text(paper.sourceFileUrl == null ? 'Upload File' : 'Replace File'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.view_list_outlined),
                  title: const Text('Manage Sections & Questions'),
                  trailing: sectionsAsync.maybeWhen(
                    data: (sections) => Text('${sections.length} section(s)'),
                    orElse: () => null,
                  ),
                  onTap: () => context.push('/admin/papers/${paper.id}/sections'),
                ),
              ),
            ],
          ),
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(paperByIdProvider(widget.paperId)),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
