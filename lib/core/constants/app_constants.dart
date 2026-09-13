/// App-wide constants. No year-based constructs are permitted anywhere in
/// this app: content is organized strictly as Phase -> Subject -> Paper.
class AppConstants {
  AppConstants._();

  static const String appName = 'Induction Program Past Papers';
  static const String appTagline = 'KP Teacher Induction Program Preparation';

  /// The 3 fixed phases. Order matters for display.
  static const List<String> phaseSlugs = ['phase-2', 'phase-3', 'phase-4'];
  static const Map<String, String> phaseNames = {
    'phase-2': 'Phase II',
    'phase-3': 'Phase III',
    'phase-4': 'Phase IV',
  };

  /// The 8 fixed subjects. Order matters for display.
  static const List<String> subjectSlugs = [
    'english',
    'mathematics',
    'general-science',
    'islamiat-nazra-quran',
    'ict-in-education',
    'classroom-management-assessment',
    'educational-psychology',
    'curriculum-and-instruction',
  ];
  static const Map<String, String> subjectNames = {
    'english': 'English',
    'mathematics': 'Mathematics',
    'general-science': 'General Science',
    'islamiat-nazra-quran': 'Islamiat / Nazra Quran',
    'ict-in-education': 'Use of ICT in Education',
    'classroom-management-assessment': 'Classroom Management and Assessment',
    'educational-psychology': 'Educational Psychology',
    'curriculum-and-instruction': 'Curriculum and Instruction',
  };

  static const int totalExpectedPapers = 24; // 3 phases x 8 subjects

  static const String originalPapersBucket = 'original-papers';

  // Cache keys
  static const String cachePhasesKey = 'cache_phases';
  static const String cacheSubjectsKey = 'cache_subjects';
  static const String cachePapersPrefix = 'cache_papers_';
  static const String cacheQuestionsPrefix = 'cache_questions_';
  static const String cacheThemeModeKey = 'cache_theme_mode';
  static const String cacheLocaleKey = 'cache_locale';

  static const Duration searchDebounce = Duration(milliseconds: 350);
}

enum QualityStatus {
  verified,
  questionable,
  paperError,
  ocrUncertain,
  answerUncertain,
}

extension QualityStatusX on QualityStatus {
  static QualityStatus fromString(String? value) {
    switch (value) {
      case 'VERIFIED':
        return QualityStatus.verified;
      case 'QUESTIONABLE':
        return QualityStatus.questionable;
      case 'PAPER_ERROR':
        return QualityStatus.paperError;
      case 'OCR_UNCERTAIN':
        return QualityStatus.ocrUncertain;
      case 'ANSWER_UNCERTAIN':
        return QualityStatus.answerUncertain;
      default:
        return QualityStatus.verified;
    }
  }

  String get dbValue {
    switch (this) {
      case QualityStatus.verified:
        return 'VERIFIED';
      case QualityStatus.questionable:
        return 'QUESTIONABLE';
      case QualityStatus.paperError:
        return 'PAPER_ERROR';
      case QualityStatus.ocrUncertain:
        return 'OCR_UNCERTAIN';
      case QualityStatus.answerUncertain:
        return 'ANSWER_UNCERTAIN';
    }
  }

  String get label {
    switch (this) {
      case QualityStatus.verified:
        return 'Verified';
      case QualityStatus.questionable:
        return 'Quality Check';
      case QualityStatus.paperError:
        return 'Paper Error';
      case QualityStatus.ocrUncertain:
        return 'Scan/OCR Uncertain';
      case QualityStatus.answerUncertain:
        return 'Answer Key Discrepancy';
    }
  }

  bool get requiresWarningBadge => this != QualityStatus.verified;
}

enum QuestionType { mcq, short, long }

extension QuestionTypeX on QuestionType {
  static QuestionType fromString(String? value) {
    switch (value) {
      case 'mcq':
        return QuestionType.mcq;
      case 'short':
        return QuestionType.short;
      case 'long':
        return QuestionType.long;
      default:
        return QuestionType.mcq;
    }
  }

  String get dbValue {
    switch (this) {
      case QuestionType.mcq:
        return 'mcq';
      case QuestionType.short:
        return 'short';
      case QuestionType.long:
        return 'long';
    }
  }
}

enum ContentStatus { draft, underReview, verified, published, archived }

extension ContentStatusX on ContentStatus {
  static ContentStatus fromString(String? value) {
    switch (value) {
      case 'DRAFT':
        return ContentStatus.draft;
      case 'UNDER_REVIEW':
        return ContentStatus.underReview;
      case 'VERIFIED':
        return ContentStatus.verified;
      case 'PUBLISHED':
        return ContentStatus.published;
      case 'ARCHIVED':
        return ContentStatus.archived;
      default:
        return ContentStatus.draft;
    }
  }
}
