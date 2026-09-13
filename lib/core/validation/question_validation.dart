import '../constants/app_constants.dart';
import '../errors/app_exception.dart';

/// One MCQ option candidate, as edited in the admin question form —
/// deliberately not the persisted QuestionOption model, since this
/// validates form input before anything is saved.
typedef OptionDraft = ({String label, String text, bool isCorrect});

/// Pure, side-effect-free validation for saving a question. Used by
/// AdminRepository.saveQuestion before any network call, and directly
/// unit-tested in test/unit/question_validation_test.dart. Keeping this
/// logic out of the repository method means a broken rule fails fast in
/// a test rather than surfacing as a confusing Postgres error.
///
/// Throws an [AppException] describing the first rule violated; returns
/// normally when the draft is valid.
class QuestionValidation {
  QuestionValidation._();

  static void validate({
    required QuestionType questionType,
    required QualityStatus qualityStatus,
    String? qualityNote,
    List<OptionDraft> options = const [],
  }) {
    // Every non-VERIFIED question must explain why — see spec section 3
    // "Quality Check" and CLAUDE.md "Content Rules".
    if (qualityStatus != QualityStatus.verified &&
        (qualityNote == null || qualityNote.trim().isEmpty)) {
      throw const AppException(
        'A quality_note is required whenever quality_status is not VERIFIED.',
      );
    }

    if (questionType != QuestionType.mcq) return;

    if (options.length < 2) {
      throw const AppException('An MCQ must have at least 2 options.');
    }

    final labels = options.map((o) => o.label.trim()).toList();
    if (labels.any((l) => l.isEmpty)) {
      throw const AppException('Every option must have a label.');
    }
    if (labels.toSet().length != labels.length) {
      throw const AppException('Option labels must be unique.');
    }

    final correctCount = options.where((o) => o.isCorrect).length;
    if (correctCount == 0) {
      throw const AppException(
        'Select which option is the verified correct answer.',
      );
    }
    if (correctCount > 1) {
      throw const AppException('Exactly one option must be marked correct.');
    }
  }

  /// Computes verification_status from the supplied original_marked_option
  /// vs. the option marked verified-correct — the exact PAPER_ANSWER_ERROR
  /// discrepancy rule from spec section 5. A blank/null original marking
  /// means "not specified", never a mismatch.
  static String resolveVerificationStatus({
    required String? originalMarkedOption,
    required String? verifiedCorrectLabel,
  }) {
    final original = originalMarkedOption?.trim();
    if (original == null || original.isEmpty) return 'VERIFIED';
    return original == verifiedCorrectLabel ? 'VERIFIED' : 'PAPER_ANSWER_ERROR';
  }
}
