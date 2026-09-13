import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/supabase_service.dart';
import '../../core/validation/content_import_validation.dart';
import '../../core/validation/paper_status.dart';
import '../../core/validation/question_validation.dart';
import '../models/admin_dashboard_stats.dart';
import '../models/audit_log.dart';
import '../models/paper.dart';
import '../models/paper_section.dart';
import '../models/question.dart';

/// Admin-only writes to official content tables. Every method here is a
/// UX convenience — the real access control is Postgres RLS requiring
/// profiles.is_admin = true (see supabase/migrations/002_rls.sql), and
/// paper status transitions are additionally re-validated inside the
/// admin_transition_paper_status Postgres function (see
/// supabase/migrations/006_admin_workflow.sql) so a client can never
/// force an illegal transition or publish content with unresolved
/// critical quality errors, no matter what the Flutter UI allows.
class AdminRepository {
  /// Admins can see every paper (any content_status), unlike
  /// PaperRepository which only ever returns PUBLISHED papers.
  Future<List<Paper>> getAllPapers() async {
    final rows = await SupabaseService.client
        .from('papers')
        .select()
        .order('created_at', ascending: false);
    return rows.map((r) => Paper.fromJson(r)).toList();
  }

  Future<Paper> createPaper({
    required String phaseId,
    required String subjectId,
    required String title,
    String? cadre,
    int? totalMarks,
    int? durationMinutes,
  }) async {
    final row = await SupabaseService.client
        .from('papers')
        .insert({
          'phase_id': phaseId,
          'subject_id': subjectId,
          'title': title,
          'cadre': cadre,
          'total_marks': totalMarks,
          'duration_minutes': durationMinutes,
          'content_status': 'DRAFT',
          'verification_status': 'DRAFT',
        })
        .select()
        .single();
    final paper = Paper.fromJson(row);
    await _logAudit(action: 'CREATE', tableName: 'papers', recordId: paper.id, after: row);
    return paper;
  }

  /// Bulk-imports one paper's sections/questions/options from JSON matching
  /// the shape documented in `docs/CONTENT_IMPORT_GUIDE.md` — the in-app
  /// counterpart to `scripts/import_content.dart`. Unlike that script, this
  /// runs as the signed-in admin's own session (gated by the same
  /// admin-write RLS every other admin write goes through), never a
  /// service-role key.
  ///
  /// Re-validates with [ContentImportValidator] regardless of any
  /// client-side check the caller already did — a critical error always
  /// blocks the import, never just a warning in the UI. If a paper already
  /// exists for this phase/subject slot, its sections (and their
  /// questions/options, via cascade) are replaced with the imported
  /// content — if that paper was VERIFIED/PUBLISHED, the
  /// invalidate_verification_on_content_change trigger
  /// (006_admin_workflow.sql) demotes it to UNDER_REVIEW automatically,
  /// same as any other edit; importing never sets a paper straight to
  /// PUBLISHED.
  Future<Paper> importPaperFromJson({
    required String phaseId,
    required String subjectId,
    required Map<String, dynamic> paperJson,
  }) async {
    final report = ContentImportValidator.validate(paperJson);
    if (report.hasCriticalErrors) {
      throw AppException(
        'Import blocked by ${report.errors.length} critical error(s):\n'
        '${report.errors.map((e) => '• ${e.message}').join('\n')}',
      );
    }

    final existing = await SupabaseService.client
        .from('papers')
        .select('id')
        .eq('phase_id', phaseId)
        .eq('subject_id', subjectId)
        .maybeSingle();

    final paperFields = {
      'title': paperJson['title'],
      'cadre': paperJson['cadre'],
      'total_marks': paperJson['total_marks'],
      'duration_minutes': paperJson['duration_minutes'],
    };

    String paperId;
    if (existing != null) {
      paperId = existing['id'] as String;
      await SupabaseService.client.from('papers').update(paperFields).eq('id', paperId);
      // Sections cascade-delete their questions/options — a re-import
      // fully replaces prior content for this slot rather than appending.
      await SupabaseService.client.from('paper_sections').delete().eq('paper_id', paperId);
    } else {
      final row = await SupabaseService.client
          .from('papers')
          .insert({
            'phase_id': phaseId,
            'subject_id': subjectId,
            ...paperFields,
            'content_status': 'DRAFT',
            'verification_status': 'DRAFT',
          })
          .select('id')
          .single();
      paperId = row['id'] as String;
    }

    var sectionOrder = 0;
    for (final rawSection in paperJson['sections'] as List) {
      final section = rawSection as Map<String, dynamic>;
      final sectionRow = await SupabaseService.client
          .from('paper_sections')
          .insert({
            'paper_id': paperId,
            'section_name': section['section_name'],
            'section_code': section['section_code'],
            'marks': section['marks'],
            'instructions': section['instructions'],
            'display_order': sectionOrder++,
          })
          .select('id')
          .single();
      final sectionId = sectionRow['id'] as String;

      var questionOrder = 0;
      for (final rawQuestion in (section['questions'] as List? ?? const [])) {
        final question = rawQuestion as Map<String, dynamic>;
        final questionRow = await SupabaseService.client
            .from('questions')
            .insert({
              'paper_section_id': sectionId,
              'question_number': question['question_number'],
              'question_type': question['question_type'],
              'question_text': question['question_text'],
              'marks': question['marks'],
              'original_marked_option': question['original_marked_option'],
              'verified_answer': question['verified_answer'],
              'verification_status': question['verification_status'] ?? 'VERIFIED',
              'explanation': question['explanation'],
              'quality_status': question['quality_status'],
              'quality_note': question['quality_note'],
              'display_order': questionOrder++,
            })
            .select('id')
            .single();
        final questionId = questionRow['id'] as String;

        if (question['question_type'] == 'mcq') {
          var optionOrder = 0;
          for (final rawOption in (question['options'] as List? ?? const [])) {
            final option = rawOption as Map<String, dynamic>;
            await SupabaseService.client.from('question_options').insert({
              'question_id': questionId,
              'option_label': option['option_label'],
              'option_text': option['option_text'],
              'is_verified_correct': option['is_verified_correct'] ?? false,
              'display_order': optionOrder++,
            });
          }
        }
      }
    }

    await _logAudit(
      action: 'IMPORT',
      tableName: 'papers',
      recordId: paperId,
      after: {'title': paperJson['title'], 'sections': (paperJson['sections'] as List).length},
    );

    final row = await SupabaseService.client.from('papers').select().eq('id', paperId).single();
    return Paper.fromJson(row);
  }

  Future<Paper> updatePaper({
    required String paperId,
    required String title,
    String? cadre,
    int? totalMarks,
    int? durationMinutes,
  }) async {
    final userId = SupabaseService.currentUser?.id;
    final before = await SupabaseService.client
        .from('papers')
        .select()
        .eq('id', paperId)
        .single();
    final row = await SupabaseService.client
        .from('papers')
        .update({
          'title': title,
          'cadre': cadre,
          'total_marks': totalMarks,
          'duration_minutes': durationMinutes,
          'updated_by': userId,
          'version': ((before['version'] as num?)?.toInt() ?? 1) + 1,
        })
        .eq('id', paperId)
        .select()
        .single();
    await _logAudit(
      action: 'UPDATE',
      tableName: 'papers',
      recordId: paperId,
      before: before,
      after: row,
    );
    return Paper.fromJson(row);
  }

  /// Uploads the original scanned paper to the `original-papers` bucket at
  /// `phase-{slug}/{subject-slug}/original.{ext}` and records the resulting
  /// public URL on the paper row. The original file itself is never
  /// mutated in place by the app — a re-upload replaces the storage object
  /// but the paper's version/audit trail records that a file changed.
  Future<void> uploadOriginalPaperFile({
    required String paperId,
    required String phaseSlug,
    required String subjectSlug,
    required Uint8List bytes,
    required String extension,
  }) async {
    final fileType = extension.toLowerCase() == 'pdf' ? 'pdf' : 'image';
    final path = '$phaseSlug/$subjectSlug/original.$extension';

    await SupabaseService.client.storage.from(AppConstants.originalPapersBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final publicUrl =
        SupabaseService.client.storage.from(AppConstants.originalPapersBucket).getPublicUrl(path);

    await SupabaseService.client.from('papers').update({
      'source_file_url': publicUrl,
      'source_file_type': fileType,
    }).eq('id', paperId);

    await _logAudit(
      action: 'UPDATE',
      tableName: 'papers',
      recordId: paperId,
      after: {'source_file_url': publicUrl, 'source_file_type': fileType},
    );
  }

  /// The only sanctioned way to change a paper's content_status. Delegates
  /// to the admin_transition_paper_status Postgres function, which
  /// re-validates the transition and the quality gate server-side and
  /// writes its own audit_logs row — see 006_admin_workflow.sql. A client
  /// bypassing PaperStatusTransitions/PaperQualityChecker entirely still
  /// can't force an illegal or unqualified transition.
  Future<void> transitionPaperStatus({
    required String paperId,
    required String newStatus,
    String? notes,
  }) async {
    try {
      await SupabaseService.client.rpc('admin_transition_paper_status', params: {
        'p_paper_id': paperId,
        'p_new_status': newStatus,
        'p_notes': notes,
      });
    } on PostgrestException catch (e) {
      throw AppException(e.message);
    }
  }

  Future<List<PaperSection>> getSections(String paperId) async {
    final rows = await SupabaseService.client
        .from('paper_sections')
        .select()
        .eq('paper_id', paperId)
        .order('display_order');
    return rows.map((r) => PaperSection.fromJson(r)).toList();
  }

  /// Sections paired with their questions, for the quality checker and the
  /// Paper Review screen.
  Future<List<SectionQuestions>> getPaperContent(String paperId) async {
    final sections = await getSections(paperId);
    final result = <SectionQuestions>[];
    for (final section in sections) {
      final questions = await getQuestions(section.id);
      result.add((section: section, questions: questions));
    }
    return result;
  }

  Future<PaperSection> createSection({
    required String paperId,
    required String sectionName,
    required String sectionCode,
    int? marks,
    String? instructions,
    required int displayOrder,
  }) async {
    final row = await SupabaseService.client
        .from('paper_sections')
        .insert({
          'paper_id': paperId,
          'section_name': sectionName,
          'section_code': sectionCode,
          'marks': marks,
          'instructions': instructions,
          'display_order': displayOrder,
        })
        .select()
        .single();
    final section = PaperSection.fromJson(row);
    await _logAudit(action: 'CREATE', tableName: 'paper_sections', recordId: section.id, after: row);
    return section;
  }

  Future<void> deleteSection(String sectionId) async {
    await SupabaseService.client.from('paper_sections').delete().eq('id', sectionId);
    await _logAudit(action: 'DELETE', tableName: 'paper_sections', recordId: sectionId);
  }

  Future<Question> getQuestion(String questionId) async {
    final row = await SupabaseService.client
        .from('questions')
        .select('*, question_options(*)')
        .eq('id', questionId)
        .single();
    return Question.fromJson(row);
  }

  Future<List<Question>> getQuestions(String sectionId) async {
    final rows = await SupabaseService.client
        .from('questions')
        .select('*, question_options(*)')
        .eq('paper_section_id', sectionId)
        .order('display_order');
    return rows.map((r) => Question.fromJson(r)).toList();
  }

  /// Inserts or updates a question along with its MCQ options (options are
  /// fully replaced on update — simplest way to keep labels/order/correct
  /// flag consistent without diffing). If the question's paper is
  /// currently VERIFIED/PUBLISHED, the invalidate_verification_on_content_change
  /// trigger (006_admin_workflow.sql) automatically demotes it to
  /// UNDER_REVIEW — a modified verified question can never keep sitting
  /// under a stale VERIFIED/PUBLISHED paper.
  Future<Question> saveQuestion({
    String? questionId,
    required String sectionId,
    required int questionNumber,
    required QuestionType questionType,
    required String questionText,
    int? marks,
    String? originalMarkedOption,
    String? verifiedAnswer,
    required String verificationStatus,
    String? explanation,
    required QualityStatus qualityStatus,
    String? qualityNote,
    required int displayOrder,
    List<OptionDraft> options = const [],
  }) async {
    QuestionValidation.validate(
      questionType: questionType,
      qualityStatus: qualityStatus,
      qualityNote: qualityNote,
      options: options,
    );

    final payload = {
      'paper_section_id': sectionId,
      'question_number': questionNumber,
      'question_type': questionType.dbValue,
      'question_text': questionText,
      'marks': marks,
      'original_marked_option': originalMarkedOption,
      'verified_answer': verifiedAnswer,
      'verification_status': verificationStatus,
      'explanation': explanation,
      'quality_status': qualityStatus.dbValue,
      'quality_note': qualityNote,
      'display_order': displayOrder,
    };

    String savedId;
    final auditAction = questionId == null ? 'CREATE' : 'UPDATE';
    if (questionId == null) {
      final row =
          await SupabaseService.client.from('questions').insert(payload).select().single();
      savedId = row['id'] as String;
    } else {
      await SupabaseService.client.from('questions').update(payload).eq('id', questionId);
      savedId = questionId;
      // Replace existing options wholesale to avoid diffing label/order/correctness.
      await SupabaseService.client.from('question_options').delete().eq('question_id', savedId);
    }

    if (questionType == QuestionType.mcq) {
      var order = 0;
      for (final option in options) {
        await SupabaseService.client.from('question_options').insert({
          'question_id': savedId,
          'option_label': option.label,
          'option_text': option.text,
          'is_verified_correct': option.isCorrect,
          'display_order': order++,
        });
      }
    }

    final row = await SupabaseService.client
        .from('questions')
        .select('*, question_options(*)')
        .eq('id', savedId)
        .single();
    await _logAudit(action: auditAction, tableName: 'questions', recordId: savedId, after: payload);
    return Question.fromJson(row);
  }

  Future<void> deleteQuestion(String questionId) async {
    await SupabaseService.client.from('questions').delete().eq('id', questionId);
    await _logAudit(action: 'DELETE', tableName: 'questions', recordId: questionId);
  }

  /// Persists a new order for a section's questions — each question keeps
  /// its id; only question_number/display_order change (see
  /// QuestionReorder, the pure logic this wraps). If the paper this
  /// section belongs to is currently VERIFIED/PUBLISHED, the
  /// invalidate_verification_on_content_change trigger
  /// (006_admin_workflow.sql) demotes it to UNDER_REVIEW automatically,
  /// same as any other question edit.
  Future<void> reorderQuestions(List<Question> orderedQuestions) async {
    for (final q in orderedQuestions) {
      await SupabaseService.client.from('questions').update({
        'question_number': q.questionNumber,
        'display_order': q.displayOrder,
      }).eq('id', q.id);
    }
    await _logAudit(
      action: 'REORDER',
      tableName: 'questions',
      after: {'ordered_question_ids': orderedQuestions.map((q) => q.id).toList()},
    );
  }

  /// Every non-VERIFIED question across every paper (draft or published),
  /// for the human-review queue.
  Future<List<Question>> getQuestionableQuestions() async {
    final rows = await SupabaseService.client
        .from('questions')
        .select('*, question_options(*)')
        .neq('quality_status', 'VERIFIED')
        .order('created_at', ascending: false);
    return rows.map((r) => Question.fromJson(r)).toList();
  }

  Future<List<AuditLog>> getRecentAuditLogs({int limit = 100}) async {
    final rows = await SupabaseService.client
        .from('audit_logs')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map((r) => AuditLog.fromJson(r)).toList();
  }

  /// Real database-derived counts for the admin dashboard — no field here
  /// is ever estimated or hard-coded; an empty database yields all zeros.
  Future<AdminDashboardStats> getDashboardStats() async {
    final client = SupabaseService.client;

    final paperRows = await client.from('papers').select('content_status, source_file_url');
    var draft = 0, needsReview = 0, verified = 0, published = 0, archived = 0, missingSource = 0;
    for (final row in paperRows) {
      final status = row['content_status'] as String?;
      final hasSource = (row['source_file_url'] as String?)?.isNotEmpty ?? false;
      if (!hasSource && status == PaperStatus.draft) missingSource++;
      switch (status) {
        case PaperStatus.draft:
          draft++;
        case PaperStatus.underReview:
          needsReview++;
        case PaperStatus.verified:
          verified++;
        case PaperStatus.published:
          published++;
        case PaperStatus.archived:
          archived++;
      }
    }

    final publishedPapersRows = await client
        .from('papers')
        .select('phase_id, phases(name)')
        .eq('content_status', 'PUBLISHED');
    final publishedByPhaseName = <String, int>{
      for (final name in AppConstants.phaseNames.values) name: 0,
    };
    for (final row in publishedPapersRows) {
      final phase = row['phases'] as Map<String, dynamic>?;
      final name = phase?['name'] as String?;
      if (name != null && publishedByPhaseName.containsKey(name)) {
        publishedByPhaseName[name] = publishedByPhaseName[name]! + 1;
      }
    }

    final subjectRows = await client.from('subjects').select('id');
    final userRows = await client.from('profiles').select('id');

    final questionRows = await client.from('questions').select('question_type, quality_status');
    var mcq = 0, short = 0, long = 0;
    var qVerified = 0, questionable = 0, ocrUncertain = 0, paperError = 0, answerUncertain = 0;
    for (final row in questionRows) {
      switch (row['question_type']) {
        case 'mcq':
          mcq++;
        case 'short':
          short++;
        case 'long':
          long++;
      }
      switch (row['quality_status']) {
        case 'VERIFIED':
          qVerified++;
        case 'QUESTIONABLE':
          questionable++;
        case 'OCR_UNCERTAIN':
          ocrUncertain++;
        case 'PAPER_ERROR':
          paperError++;
        case 'ANSWER_UNCERTAIN':
          answerUncertain++;
      }
    }

    return AdminDashboardStats(
      totalPapers: paperRows.length,
      draftPapers: draft,
      needsReviewPapers: needsReview,
      verifiedPapers: verified,
      publishedPapers: published,
      archivedPapers: archived,
      missingSourcePapers: missingSource,
      publishedByPhaseName: publishedByPhaseName,
      totalSubjects: subjectRows.length,
      totalQuestions: questionRows.length,
      mcqCount: mcq,
      shortCount: short,
      longCount: long,
      verifiedQuestionCount: qVerified,
      questionableCount: questionable,
      ocrUncertainCount: ocrUncertain,
      paperErrorCount: paperError,
      answerUncertainCount: answerUncertain,
      totalUsers: userRows.length,
    );
  }

  /// Best-effort audit trail write. Never blocks the primary operation:
  /// a logging failure (e.g. a transient network blip right after a
  /// successful write) is swallowed rather than surfaced as if the actual
  /// content change had failed.
  Future<void> _logAudit({
    required String action,
    required String tableName,
    String? recordId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) async {
    try {
      await SupabaseService.client.from('audit_logs').insert({
        'actor_id': SupabaseService.currentUser?.id,
        'action': action,
        'table_name': tableName,
        'record_id': recordId,
        'before_data': before,
        'after_data': after,
      });
    } catch (_) {
      // Intentionally swallowed — see doc comment above.
    }
  }
}
