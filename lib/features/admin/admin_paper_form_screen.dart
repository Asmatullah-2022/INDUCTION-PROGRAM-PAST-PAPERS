import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../home/home_providers.dart';
import '../phases/phase_screen.dart' show subjectsProvider;
import 'admin_guard.dart';
import 'admin_providers.dart';

/// Creates a new DRAFT paper for a phase/subject slot. Papers are unique
/// per (phase_id, subject_id) — the DB constraint rejects a duplicate slot,
/// surfaced here as a normal form error rather than a crash.
class AdminPaperFormScreen extends ConsumerStatefulWidget {
  const AdminPaperFormScreen({super.key});

  @override
  ConsumerState<AdminPaperFormScreen> createState() => _AdminPaperFormScreenState();
}

class _AdminPaperFormScreenState extends ConsumerState<AdminPaperFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _cadreController = TextEditingController();
  final _totalMarksController = TextEditingController();
  final _durationController = TextEditingController();
  String? _phaseId;
  String? _subjectId;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _cadreController.dispose();
    _totalMarksController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_phaseId == null || _subjectId == null) {
      setState(() => _error = 'Select a phase and a subject.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final paper = await ref.read(adminRepositoryProvider).createPaper(
            phaseId: _phaseId!,
            subjectId: _subjectId!,
            title: _titleController.text.trim(),
            cadre: _cadreController.text.trim().isEmpty ? null : _cadreController.text.trim(),
            totalMarks: int.tryParse(_totalMarksController.text.trim()),
            durationMinutes: int.tryParse(_durationController.text.trim()),
          );
      ref.invalidate(adminAllPapersProvider);
      if (mounted) context.pushReplacement('/admin/papers/${paper.id}');
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      final message = e.toString();
      setState(() => _error = message.contains('duplicate key') || message.contains('23505')
          ? 'A paper already exists for this phase/subject slot.'
          : 'Could not create paper: $message');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phasesAsync = ref.watch(phasesProvider);
    final subjectsAsync = ref.watch(subjectsProvider);

    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('New Paper')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_error!),
                ),
                const SizedBox(height: 16),
              ],
              Text('Phase', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              phasesAsync.when(
                data: (phases) => Wrap(
                  spacing: 8,
                  children: phases
                      .map((p) => ChoiceChip(
                            label: Text(p.name),
                            selected: _phaseId == p.id,
                            onSelected: (_) => setState(() => _phaseId = p.id),
                          ))
                      .toList(),
                ),
                loading: () => const CircularProgressIndicator(strokeWidth: 2),
                error: (e, st) => Text('$e'),
              ),
              const SizedBox(height: 20),
              Text('Subject', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              subjectsAsync.when(
                data: (subjects) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: subjects
                      .map((s) => ChoiceChip(
                            label: Text(s.name),
                            selected: _subjectId == s.id,
                            onSelected: (_) => setState(() => _subjectId = s.id),
                          ))
                      .toList(),
                ),
                loading: () => const CircularProgressIndicator(strokeWidth: 2),
                error: (e, st) => Text('$e'),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cadreController,
                decoration: const InputDecoration(labelText: 'Cadre (optional)'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _totalMarksController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Total Marks'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _durationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Duration (minutes)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _submit,
                child: _isSaving
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Paper (as DRAFT)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
