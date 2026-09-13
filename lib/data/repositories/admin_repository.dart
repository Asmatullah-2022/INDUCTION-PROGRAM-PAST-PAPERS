import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/supabase_service.dart';
import '../../core/validation/question_validation.dart';
import '../models/paper.dart';
import '../models/paper_section.dart';
import '../models/question.dart';

/// Admin-only writes to official content tables. Every method here is a
/// UX convenience — the real access control is Postgres RLS requiring
/// profiles.is_admin = true (see supabase/migrations/002_rls.sql). If the
/// requesting user isn't actually an admin, these calls fail server-side
/// regardless of what the client believes.
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
    final row = await SupabaseService.client
        .from('papers')
        .update({
          'title': title,
          'cadre': cadre,
          'total_marks': totalMarks,
          'duration_minutes': durationMinutes,
          'updated_by': userId,
          'version': await _incrementedVersion(paperId),
        })
        .eq('id', paperId)
        .select()
        .single();
    return Paper.fromJson(row);
  }

  Future<int> _incrementedVersion(String paperId) async {
    final row = await SupabaseService.client
        .from('papers')
        .select('version')
        .eq('id', paperId)
        .single();
    return ((row['version'] as num?)?.toInt() ?? 1) + 1;
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
  }

  /// Publishing is always an explicit, separate admin action — never
  /// triggered automatically by content import or editing.
  Future<void> setContentStatus({required String paperId, required String status}) async {
    if (!{'DRAFT', 'UNDER_REVIEW', 'VERIFIED', 'PUBLISHED', 'ARCHIVED'}.contains(status)) {
      throw AppException('Invalid content status: $status');
    }
    await SupabaseService.client
        .from('papers')
        .update({'content_status': status}).eq('id', paperId);
  }

  Future<List<PaperSection>> getSections(String paperId) async {
    final rows = await SupabaseService.client
        .from('paper_sections')
        .select()
        .eq('paper_id', paperId)
        .order('display_order');
    return rows.map((r) => PaperSection.fromJson(r)).toList();
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
    return PaperSection.fromJson(row);
  }

  Future<void> deleteSection(String sectionId) async {
    await SupabaseService.client.from('paper_sections').delete().eq('id', sectionId);
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
  /// flag consistent without diffing).
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
    return Question.fromJson(row);
  }

  Future<void> deleteQuestion(String questionId) async {
    await SupabaseService.client.from('questions').delete().eq('id', questionId);
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
}
