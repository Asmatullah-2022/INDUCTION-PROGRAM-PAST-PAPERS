import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/downloads_service.dart';
import '../../data/models/download_record.dart';
import '../../shared/widgets/state_widgets.dart';
import 'downloads_providers.dart';

/// Lists locally-saved PDFs (generated answer keys/solved questions, or
/// a paper's original source file) with Open/Share/Delete — see
/// DownloadsService for what's actually persisted and why it's never a
/// separate authorization path from the RLS-gated content the app
/// already showed the user.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(downloadsProvider);
    final formatter = DateFormat('MMM d, yyyy • HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: records.isEmpty
          ? const EmptyState(
              icon: Icons.download_outlined,
              title: 'No downloads yet',
              subtitle: 'Downloaded answer keys, solved papers, and original papers appear here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _DownloadTile(record: records[index], formatter: formatter),
            ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  final DownloadRecord record;
  final DateFormat formatter;

  const _DownloadTile({required this.record, required this.formatter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = !DownloadsService.fileExists(record);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.picture_as_pdf_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.paperTitle,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text('${record.phaseName} • ${record.subjectName}',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(record.documentType.label,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _InfoChip(icon: Icons.calendar_today_outlined, label: formatter.format(record.downloadedAt)),
                const SizedBox(width: 8),
                _InfoChip(
                    icon: Icons.sd_storage_outlined,
                    label: DownloadsService.formatFileSize(record.fileSizeBytes)),
                const SizedBox(width: 8),
                _InfoChip(icon: Icons.verified_outlined, label: record.contentStatus),
              ],
            ),
            if (missing) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Text('File missing or was removed from device storage',
                      style: TextStyle(color: scheme.error, fontSize: 12)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: missing ? null : () => _open(context, record),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open'),
                ),
                TextButton.icon(
                  onPressed: missing ? null : () => _share(context, record),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                ),
                TextButton.icon(
                  onPressed: () => _confirmDelete(context, ref, record),
                  icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
                  label: Text('Delete', style: TextStyle(color: scheme.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, DownloadRecord record) async {
    try {
      final bytes = await DownloadsService.readBytes(record);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this file. It may be corrupted.')),
        );
      }
    }
  }

  Future<void> _share(BuildContext context, DownloadRecord record) async {
    try {
      await Share.shareXFiles([XFile(record.filePath)], text: record.paperTitle);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share this file. It may be corrupted.')),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, DownloadRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete download?'),
        content: Text('This removes "${record.paperTitle}" (${record.documentType.label}) from your device.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(downloadsProvider.notifier).delete(record);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
