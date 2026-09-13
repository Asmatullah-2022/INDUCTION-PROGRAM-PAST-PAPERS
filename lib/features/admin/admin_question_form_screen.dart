import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/validation/question_validation.dart';
import '../../data/models/question.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';
import 'admin_providers.dart';

class _OptionRow {
  final TextEditingController labelController;
  final TextEditingController textController;

  _OptionRow({String label = '', String text = ''})
      : labelController = TextEditingController(text: label),
        textController = TextEditingController(text: text);

  void dispose() {
    labelController.dispose();
    textController.dispose();
  }
}

/// Create/edit form for one question (MCQ/short/long), including the MCQ
/// options editor. Pass questionId == null to create a new question.
class AdminQuestionFormScreen extends ConsumerStatefulWidget {
  final String sectionId;
  final String? questionId;

  const AdminQuestionFormScreen({
    super.key,
    required this.sectionId,
    this.questionId,
  });

  @override
  ConsumerState<AdminQuestionFormScreen> createState() => _AdminQuestionFormScreenState();
}

class _AdminQuestionFormScreenState extends ConsumerState<AdminQuestionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionNumberController = TextEditingController();
  final _questionTextController = TextEditingController();
  final _marksController = TextEditingController();
  final _verifiedAnswerController = TextEditingController();
  final _explanationController = TextEditingController();
  final _qualityNoteController = TextEditingController();

  QuestionType _questionType = QuestionType.mcq;
  QualityStatus _qualityStatus = QualityStatus.verified;
  String? _originalMarkedOption;
  final List<_OptionRow> _options = [];
  int _correctOptionIndex = -1;
  bool _isSaving = false;
  String? _error;
  bool _loadedExisting = false;

  bool get _isEditing => widget.questionId != null;

  @override
  void initState() {
    super.initState();
    if (!_isEditing) {
      _options.addAll([_OptionRow(label: 'A'), _OptionRow(label: 'B')]);
    }
  }

  @override
  void dispose() {
    _questionNumberController.dispose();
    _questionTextController.dispose();
    _marksController.dispose();
    _verifiedAnswerController.dispose();
    _explanationController.dispose();
    _qualityNoteController.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  void _loadFromQuestion(Question q) {
    if (_loadedExisting) return;
    _loadedExisting = true;
    _questionNumberController.text = '${q.questionNumber}';
    _questionTextController.text = q.questionText;
    _marksController.text = q.marks?.toString() ?? '';
    _verifiedAnswerController.text = q.verifiedAnswer ?? '';
    _explanationController.text = q.explanation ?? '';
    _qualityNoteController.text = q.qualityNote ?? '';
    _questionType = q.questionType;
    _qualityStatus = q.qualityStatus;
    _originalMarkedOption = q.originalMarkedOption;
    _options.clear();
    for (final o in q.options) {
      _options.add(_OptionRow(label: o.optionLabel, text: o.optionText));
      if (o.isVerifiedCorrect) _correctOptionIndex = _options.length - 1;
    }
    if (_options.isEmpty) {
      _options.addAll([_OptionRow(label: 'A'), _OptionRow(label: 'B')]);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Guards the options[_correctOptionIndex] lookup below — everything
    // else (quality note requirement, option count, exactly-one-correct)
    // is enforced by QuestionValidation, shared with AdminRepository.
    if (_questionType == QuestionType.mcq && _correctOptionIndex < 0) {
      setState(() => _error = 'Select which option is the verified correct answer.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final options = _questionType == QuestionType.mcq
          ? _options
              .asMap()
              .entries
              .map((e) => (
                    label: e.value.labelController.text.trim(),
                    text: e.value.textController.text.trim(),
                    isCorrect: e.key == _correctOptionIndex,
                  ))
              .toList()
          : const <OptionDraft>[];

      final correctLabel =
          _questionType == QuestionType.mcq ? options[_correctOptionIndex].label : null;
      final verificationStatus = QuestionValidation.resolveVerificationStatus(
        originalMarkedOption: _questionType == QuestionType.mcq ? _originalMarkedOption : null,
        verifiedCorrectLabel: correctLabel,
      );

      await ref.read(adminRepositoryProvider).saveQuestion(
            questionId: widget.questionId,
            sectionId: widget.sectionId,
            questionNumber: int.parse(_questionNumberController.text.trim()),
            questionType: _questionType,
            questionText: _questionTextController.text.trim(),
            marks: int.tryParse(_marksController.text.trim()),
            originalMarkedOption:
                _originalMarkedOption?.isEmpty == true ? null : _originalMarkedOption,
            verifiedAnswer: _questionType == QuestionType.mcq
                ? correctLabel
                : _verifiedAnswerController.text.trim(),
            verificationStatus: verificationStatus,
            explanation:
                _explanationController.text.trim().isEmpty ? null : _explanationController.text.trim(),
            qualityStatus: _qualityStatus,
            qualityNote:
                _qualityNoteController.text.trim().isEmpty ? null : _qualityNoteController.text.trim(),
            displayOrder: int.tryParse(_questionNumberController.text.trim()) ?? 0,
            options: options,
          );

      ref.invalidate(adminQuestionsProvider(widget.sectionId));
      if (widget.questionId != null) ref.invalidate(adminQuestionProvider(widget.questionId!));
      ref.invalidate(adminQuestionableQuestionsProvider);
      if (mounted) context.pop();
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not save question: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing) {
      return AdminGuard(child: Scaffold(appBar: AppBar(title: const Text('New Question')), body: _buildForm()));
    }
    final questionAsync = ref.watch(adminQuestionProvider(widget.questionId!));
    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit Question')),
        body: questionAsync.when(
          data: (q) {
            _loadFromQuestion(q);
            return _buildForm();
          },
          loading: () => const LoadingList(),
          error: (e, st) => ErrorState(message: e.toString()),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
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
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _questionNumberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Question Number'),
                  validator: (v) => (v == null || int.tryParse(v.trim()) == null)
                      ? 'Enter a valid number'
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _marksController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Marks (optional)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Question Type', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<QuestionType>(
            segments: const [
              ButtonSegment(value: QuestionType.mcq, label: Text('MCQ')),
              ButtonSegment(value: QuestionType.short, label: Text('Short')),
              ButtonSegment(value: QuestionType.long, label: Text('Long')),
            ],
            selected: {_questionType},
            onSelectionChanged: (s) => setState(() => _questionType = s.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _questionTextController,
            decoration: const InputDecoration(labelText: 'Question Text (exactly as in the original paper)'),
            maxLines: 3,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Question text is required' : null,
          ),
          const SizedBox(height: 20),
          if (_questionType == QuestionType.mcq) _buildOptionsEditor() else _buildAnswerFields(),
          const SizedBox(height: 20),
          TextFormField(
            controller: _explanationController,
            decoration: const InputDecoration(labelText: 'Explanation (optional)'),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          Text('Quality Status', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: QualityStatus.values
                .map((status) => ChoiceChip(
                      label: Text(status.label),
                      selected: _qualityStatus == status,
                      onSelected: (_) => setState(() => _qualityStatus = status),
                    ))
                .toList(),
          ),
          if (_qualityStatus != QualityStatus.verified) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _qualityNoteController,
              decoration: const InputDecoration(
                labelText: 'Quality Note (required)',
                hintText: 'Explain why this question is not fully verified',
              ),
              maxLines: 2,
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEditing ? 'Save Changes' : 'Create Question'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerFields() {
    return TextFormField(
      controller: _verifiedAnswerController,
      decoration: const InputDecoration(labelText: 'Verified Answer'),
      maxLines: 6,
      validator: (v) => (v == null || v.trim().isEmpty) ? 'A verified answer is required' : null,
    );
  }

  Widget _buildOptionsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Options', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Select the radio button next to the academically verified correct option.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Radio<int>(
                  value: i,
                  groupValue: _correctOptionIndex,
                  onChanged: (v) => setState(() => _correctOptionIndex = v!),
                ),
                SizedBox(
                  width: 56,
                  child: TextFormField(
                    controller: _options[i].labelController,
                    decoration: const InputDecoration(labelText: 'Label'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _options[i].textController,
                    decoration: const InputDecoration(labelText: 'Option Text'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _options.length <= 2
                      ? null
                      : () => setState(() {
                            _options[i].dispose();
                            _options.removeAt(i);
                            if (_correctOptionIndex == i) _correctOptionIndex = -1;
                            if (_correctOptionIndex > i) _correctOptionIndex--;
                          }),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(
              () => _options.add(_OptionRow(label: String.fromCharCode(65 + _options.length)))),
          icon: const Icon(Icons.add),
          label: const Text('Add Option'),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _originalMarkedOption,
          decoration: const InputDecoration(
            labelText: 'Original Marked Option (as ticked in the supplied paper, optional)',
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Not specified')),
            ..._options.map((o) => DropdownMenuItem(
                  value: o.labelController.text.trim(),
                  child: Text(o.labelController.text.trim()),
                )),
          ],
          onChanged: (v) => setState(() => _originalMarkedOption = v),
        ),
      ],
    );
  }
}
