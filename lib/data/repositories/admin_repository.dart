import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/pagination/paginated_result.dart';
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
  ///
  /// Fetches every section's questions in one query (`inFilter` over all
  /// section ids) instead of one query per section — the same N+1 fix as
  /// PaperRepository.getSectionsWithQuestions; see docs/PERFORMANCE_AUDIT.md.
  Future<List<SectionQuestions>> getPaperContent(String paperId) async {
    final sections = await getSections(paperId);
    if (sections.isEmpty) return const [];

    final rows = await SupabaseService.client
        .from('questions')
        .select('*, question_options(*)')
        .inFilter('paper_section_id', sections.map((s) => s.id).toList())
        .order('display_order');

    final questionsBySectionId = <String, List<Question>>{};
    for (final row in rows) {
      final question = Question.fromJson(row);
      questionsBySectionId.putIfAbsent(question.paperSectionId, () => []).add(question);
    }

    return sections
        .map((section) =>
            (section: section, questions: questionsBySectionId[section.id] ?? const <Question>[]))
        .toList();
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
  ///
  /// A single atomic RPC call (admin_reorder_questions,
  /// 009_performance_indexes_and_rpcs.sql) instead of one UPDATE per
  /// question — reordering a 30-question section previously meant 30
  /// round trips; see docs/PERFORMANCE_AUDIT.md.
  Future<void> reorderQuestions(List<Question> orderedQuestions) async {
    if (orderedQuestions.isEmpty) return;
    await SupabaseService.client.rpc('admin_reorder_questions', params: {
      'p_question_ids': orderedQuestions.map((q) => q.id).toList(),
      'p_question_numbers': orderedQuestions.map((q) => q.questionNumber).toList(),
      'p_display_orders': orderedQuestions.map((q) => q.displayOrder).toList(),
    });
    await _logAudit(
      action: 'REORDER',
      tableName: 'questions',
      after: {'ordered_question_ids': orderedQuestions.map((q) => q.id).toList()},
    );
  }

  /// One keyset-paginated page of non-VERIFIED questions across every
  /// paper (draft or published), for the human-review queue. Ordered by
  /// created_at desc, same as before, but now bounded to [limit] rows per
  /// call instead of unconditionally loading every questionable question
  /// in the database — see docs/PERFORMANCE_AUDIT.md.
  Future<PaginatedResult<Question>> getQuestionableQuestionsPage({
    String? cursor,
    int limit = 20,
  }) async {
    var query = SupabaseService.client
        .from('questions')
        .select('*, question_options(*)')
        .neq('quality_status', 'VERIFIED');
    if (cursor != null) {
      query = query.lt('created_at', cursor);
    }
    final rows = await query.order('created_at', ascending: false).limit(limit + 1);
    final hasMore = rows.length > limit;
    final page = hasMore ? rows.sublist(0, limit) : rows;
    final questions = page.map((r) => Question.fromJson(r)).toList();
    return PaginatedResult(
      items: questions,
      hasMore: hasMore,
      nextCursor: rows.isEmpty ? cursor : (page.last['created_at'] as String),
    );
  }

  /// One keyset-paginated page of the audit trail, newest first — bounded
  /// to [limit] rows per call instead of a flat top-100 with no way to
  /// see older entries. See docs/PERFORMANCE_AUDIT.md.
  Future<PaginatedResult<AuditLog>> getAuditLogsPage({
    String? cursor,
    int limit = 20,
  }) async {
    var query = SupabaseService.client.from('audit_logs').select();
    if (cursor != null) {
      query = query.lt('created_at', cursor);
    }
    final rows = await query.order('created_at', ascending: false).limit(limit + 1);
    final hasMore = rows.length > limit;
    final page = hasMore ? rows.sublist(0, limit) : rows;
    final logs = page.map((r) => AuditLog.fromJson(r)).toList();
    return PaginatedResult(
      items: logs,
      hasMore: hasMore,
      nextCursor: rows.isEmpty ? cursor : (page.last['created_at'] as String),
    );
  }

  /// Real database-derived counts for the admin dashboard — no field here
  /// is ever estimated or hard-coded; an empty database yields all zeros.
  ///
  /// A single RPC call (admin_dashboard_stats,
  /// 009_performance_indexes_and_rpcs.sql) that computes every count
  /// server-side, instead of 5 separate queries that each pulled every
  /// matching row's full columns to the client just to count them in
  /// Dart — see docs/PERFORMANCE_AUDIT.md.
  Future<AdminDashboardStats> getDashboardStats() async {
    final response = await SupabaseService.client.rpc('admin_dashboard_stats');
    final stats = response as Map<String, dynamic>;

    final publishedByPhaseIdName = (stats['published_by_phase_name'] as Map<String, dynamic>? ?? {});
    final publishedByPhaseName = <String, int>{
      for (final name in AppConstants.phaseNames.values) name: 0,
    };
    for (final entry in publishedByPhaseIdName.entries) {
      if (publishedByPhaseName.containsKey(entry.key)) {
        publishedByPhaseName[entry.key] = (entry.value as num).toInt();
      }
    }

    int count(String key) => (stats[key] as num?)?.toInt() ?? 0;

    return AdminDashboardStats(
      totalPapers: count('total_papers'),
      draftPapers: count('draft_papers'),
      needsReviewPapers: count('needs_review_papers'),
      verifiedPapers: count('verified_papers'),
      publishedPapers: count('published_papers'),
      archivedPapers: count('archived_papers'),
      missingSourcePapers: count('missing_source_papers'),
      publishedByPhaseName: publishedByPhaseName,
      totalSubjects: count('total_subjects'),
      totalQuestions: count('total_questions'),
      mcqCount: count('mcq_count'),
      shortCount: count('short_count'),
      longCount: count('long_count'),
      verifiedQuestionCount: count('verified_question_count'),
      questionableCount: count('questionable_count'),
      ocrUncertainCount: count('ocr_uncertain_count'),
      paperErrorCount: count('paper_error_count'),
      answerUncertainCount: count('answer_uncertain_count'),
      totalUsers: count('total_users'),
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
