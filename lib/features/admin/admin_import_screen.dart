import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/validation/content_import_validation.dart';
import '../home/home_providers.dart';
import '../phases/phase_screen.dart' show subjectsProvider;
import 'admin_guard.dart';
import 'admin_providers.dart';

/// In-app alternative to `scripts/import_content.dart`: pick a paper JSON
/// file (the same shape documented in `docs/CONTENT_IMPORT_GUIDE.md`),
/// see exactly what ContentImportValidator finds before anything is
/// written, and import it as the signed-in admin — gated by the same
/// RLS every other admin write goes through, no service-role key
/// involved. Never sets a paper's status to anything but DRAFT; the
/// normal Review & Publish workflow still applies afterward.
class AdminImportScreen extends ConsumerStatefulWidget {
  const AdminImportScreen({super.key});

  @override
  ConsumerState<AdminImportScreen> createState() => _AdminImportScreenState();
}

class _AdminImportScreenState extends ConsumerState<AdminImportScreen> {
  String? _fileName;
  Map<String, dynamic>? _parsed;
  ContentImportReport? _report;
  String? _parseError;
  bool _isImporting = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() {
      _fileName = file.name;
      _parsed = null;
      _report = null;
      _parseError = null;
    });

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        setState(() => _parseError = 'The file must contain one JSON object (one paper).');
        return;
      }
      setState(() {
        _parsed = decoded;
        _report = ContentImportValidator.validate(decoded);
      });
    } catch (e) {
      setState(() => _parseError = 'Invalid JSON: $e');
    }
  }

  Future<void> _import() async {
    final parsed = _parsed;
    final report = _report;
    if (parsed == null || report == null || report.hasCriticalErrors) return;

    final phases = await ref.read(phasesProvider.future);
    final subjects = await ref.read(subjectsProvider.future);
    final phase = phases.where((p) => p.slug == parsed['phase_slug']).firstOrNull;
    final subject = subjects.where((s) => s.slug == parsed['subject_slug']).firstOrNull;
    if (phase == null || subject == null) {
      setState(() => _parseError = 'Could not resolve phase_slug/subject_slug to a known phase/subject.');
      return;
    }

    setState(() => _isImporting = true);
    try {
      final paper = await ref.read(adminRepositoryProvider).importPaperFromJson(
            phaseId: phase.id,
            subjectId: subject.id,
            paperJson: parsed,
          );
      ref.invalidate(adminAllPapersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Paper imported as DRAFT.')));
        context.pushReplacement('/admin/papers/${paper.id}');
      }
    } on AppException catch (e) {
      setState(() => _parseError = e.message);
    } catch (e) {
      setState(() => _parseError = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Import Content')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Pick a paper JSON file matching the format in '
              'docs/CONTENT_IMPORT_GUIDE.md. It will be validated before '
              'anything is written, and always imports as DRAFT — publishing '
              'still goes through the normal Review & Publish workflow.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _isImporting ? null : _pickFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(_fileName ?? 'Choose JSON File'),
            ),
            if (_parseError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_parseError!),
              ),
            ],
            if (_report != null) ...[
              const SizedBox(height: 20),
              _ImportReportCard(report: _report!),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: (_report!.hasCriticalErrors || _isImporting) ? null : _import,
                child: _isImporting
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Import as Draft'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ImportReportCard extends StatelessWidget {
  final ContentImportReport report;
  const _ImportReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Validation Report', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (report.issues.isEmpty)
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text('No issues found.'),
                ],
              ),
            ...report.errors.map((e) => _row(context, e.message, color: scheme.error)),
            ...report.warnings.map((w) => _row(context, w.message, color: Colors.orange)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String message, {required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
