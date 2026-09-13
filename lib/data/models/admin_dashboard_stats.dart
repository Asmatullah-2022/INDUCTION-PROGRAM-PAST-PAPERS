/// Real database-derived counts for the admin dashboard. Every field here
/// must come from an actual query — never a placeholder/fake number. An
/// empty database is represented as all-zero, not omitted or estimated.
class AdminDashboardStats {
  final int totalPapers;
  final int draftPapers;
  final int needsReviewPapers;
  final int verifiedPapers;
  final int publishedPapers;
  final int archivedPapers;
  final int missingSourcePapers;
  final Map<String, int> publishedByPhaseName;
  final int totalSubjects;
  final int totalQuestions;
  final int mcqCount;
  final int shortCount;
  final int longCount;
  final int verifiedQuestionCount;
  final int questionableCount;
  final int ocrUncertainCount;
  final int paperErrorCount;
  final int answerUncertainCount;
  final int totalUsers;

  const AdminDashboardStats({
    required this.totalPapers,
    required this.draftPapers,
    required this.needsReviewPapers,
    required this.verifiedPapers,
    required this.publishedPapers,
    required this.archivedPapers,
    required this.missingSourcePapers,
    required this.publishedByPhaseName,
    required this.totalSubjects,
    required this.totalQuestions,
    required this.mcqCount,
    required this.shortCount,
    required this.longCount,
    required this.verifiedQuestionCount,
    required this.questionableCount,
    required this.ocrUncertainCount,
    required this.paperErrorCount,
    required this.answerUncertainCount,
    required this.totalUsers,
  });
}
