/// Optional context passed via go_router `extra` when AI Teacher is
/// opened from a specific question (see QuestionTile's "Ask AI Teacher"
/// button) rather than from the main tab. [questionPreview] is display
/// text only — the actual verified content is re-fetched server-side by
/// the ai-teacher Edge Function from [questionId], never trusted from
/// the client.
class AiTeacherContext {
  final String? paperId;
  final String? questionId;
  final String? questionPreview;
  final bool isMcq;

  const AiTeacherContext({
    this.paperId,
    this.questionId,
    this.questionPreview,
    this.isMcq = false,
  });

  bool get hasQuestion => questionId != null;
}
