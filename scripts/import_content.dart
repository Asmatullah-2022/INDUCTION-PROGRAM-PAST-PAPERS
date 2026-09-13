// Content importer: reads validated paper JSON files (see
// validate_content.dart) and upserts them into Supabase as DRAFT papers.
// Publishing (setting content_status = 'PUBLISHED') is a deliberate,
// separate admin action — this script never publishes anything itself.
//
// Usage:
//   dart run scripts/import_content.dart <content_dir> \
//     --url=$SUPABASE_URL --service-key=$SUPABASE_SERVICE_ROLE_KEY
//
// The service-role key is required here because importing official content
// bypasses RLS by design — this script is an admin/CI tool, never shipped
// in the Flutter app, and must only ever be run from a trusted machine/CI
// with the key passed as an argument or environment variable, never
// committed to source control.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run scripts/import_content.dart <content_dir> '
        '--url=<SUPABASE_URL> --service-key=<SERVICE_ROLE_KEY>');
    exit(2);
  }

  final contentDir = Directory(args[0]);
  final url = _argValue(args, 'url') ?? Platform.environment['SUPABASE_URL'];
  final serviceKey =
      _argValue(args, 'service-key') ?? Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];

  if (url == null || serviceKey == null) {
    stderr.writeln('Missing --url / --service-key (or SUPABASE_URL / '
        'SUPABASE_SERVICE_ROLE_KEY environment variables).');
    exit(2);
  }

  if (!contentDir.existsSync()) {
    stderr.writeln('Content directory not found: ${contentDir.path}');
    exit(2);
  }

  final files = contentDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList();

  if (files.isEmpty) {
    stdout.writeln('No content files to import under ${contentDir.path}.');
    return;
  }

  final client = _SupabaseAdminClient(baseUrl: url, serviceKey: serviceKey);
  final phasesBySlug = await client.fetchIdBySlug('phases');
  final subjectsBySlug = await client.fetchIdBySlug('subjects');

  for (final file in files) {
    await _importFile(file, client, phasesBySlug, subjectsBySlug);
  }

  stdout.writeln('\nImport complete. All papers were inserted as DRAFT — '
      'run the verification workflow and publish explicitly via the admin '
      'tools before they become visible to normal users.');
}

Future<void> _importFile(
  File file,
  _SupabaseAdminClient client,
  Map<String, String> phasesBySlug,
  Map<String, String> subjectsBySlug,
) async {
  final paper = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final phaseId = phasesBySlug[paper['phase_slug']];
  final subjectId = subjectsBySlug[paper['subject_slug']];

  if (phaseId == null || subjectId == null) {
    stderr.writeln('SKIP ${file.path}: unknown phase_slug/subject_slug '
        '(run validate_content.dart first).');
    return;
  }

  final paperId = await client.upsertPaper(
    phaseId: phaseId,
    subjectId: subjectId,
    title: paper['title'] as String,
    cadre: paper['cadre'] as String?,
    totalMarks: paper['total_marks'] as int?,
    durationMinutes: paper['duration_minutes'] as int?,
    sourceFileUrl: paper['source_file_url'] as String?,
    sourceFileType: paper['source_file_type'] as String?,
  );

  final sections = paper['sections'] as List<dynamic>;
  var sectionOrder = 0;
  for (final rawSection in sections) {
    final section = rawSection as Map<String, dynamic>;
    final sectionId = await client.insertSection(
      paperId: paperId,
      name: section['section_name'] as String,
      code: section['section_code'] as String,
      marks: section['marks'] as int?,
      instructions: section['instructions'] as String?,
      displayOrder: sectionOrder++,
    );

    final questions = (section['questions'] as List<dynamic>?) ?? [];
    var questionOrder = 0;
    for (final rawQuestion in questions) {
      final question = rawQuestion as Map<String, dynamic>;
      final questionId = await client.insertQuestion(
        sectionId: sectionId,
        questionNumber: question['question_number'] as int,
        questionType: question['question_type'] as String,
        questionText: question['question_text'] as String,
        marks: question['marks'] as int?,
        originalMarkedOption: question['original_marked_option'] as String?,
        verifiedAnswer: question['verified_answer'] as String?,
        verificationStatus: question['verification_status'] as String? ?? 'VERIFIED',
        explanation: question['explanation'] as String?,
        qualityStatus: question['quality_status'] as String? ?? 'VERIFIED',
        qualityNote: question['quality_note'] as String?,
        displayOrder: questionOrder++,
      );

      final options = (question['options'] as List<dynamic>?) ?? [];
      var optionOrder = 0;
      for (final rawOption in options) {
        final option = rawOption as Map<String, dynamic>;
        await client.insertOption(
          questionId: questionId,
          label: option['option_label'] as String,
          text: option['option_text'] as String,
          isVerifiedCorrect: option['is_verified_correct'] as bool? ?? false,
          displayOrder: optionOrder++,
        );
      }
    }
  }

  stdout.writeln('Imported ${file.path} as DRAFT paper $paperId '
      '(${sections.length} section(s)).');
}

String? _argValue(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring('--$name='.length);
  }
  return null;
}

/// Minimal REST wrapper over PostgREST using the service-role key. Kept
/// intentionally small (no supabase_flutter dependency) since this script
/// runs outside the Flutter app, in CI/admin tooling only.
class _SupabaseAdminClient {
  final String baseUrl;
  final String serviceKey;

  _SupabaseAdminClient({required this.baseUrl, required this.serviceKey});

  Map<String, String> get _headers => {
        'apikey': serviceKey,
        'Authorization': 'Bearer $serviceKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<Map<String, String>> fetchIdBySlug(String table) async {
    final response =
        await http.get(Uri.parse('$baseUrl/rest/v1/$table?select=id,slug'), headers: _headers);
    _checkOk(response, 'fetch $table');
    final rows = jsonDecode(response.body) as List<dynamic>;
    return {for (final r in rows) r['slug'] as String: r['id'] as String};
  }

  Future<String> upsertPaper({
    required String phaseId,
    required String subjectId,
    required String title,
    String? cadre,
    int? totalMarks,
    int? durationMinutes,
    String? sourceFileUrl,
    String? sourceFileType,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rest/v1/papers?on_conflict=phase_id,subject_id'),
      headers: {..._headers, 'Prefer': 'resolution=merge-duplicates,return=representation'},
      body: jsonEncode({
        'phase_id': phaseId,
        'subject_id': subjectId,
        'title': title,
        'cadre': cadre,
        'total_marks': totalMarks,
        'duration_minutes': durationMinutes,
        'source_file_url': sourceFileUrl,
        'source_file_type': sourceFileType,
        'content_status': 'DRAFT',
        'verification_status': 'DRAFT',
      }),
    );
    _checkOk(response, 'upsert paper "$title"');
    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows.first['id'] as String;
  }

  Future<String> insertSection({
    required String paperId,
    required String name,
    required String code,
    int? marks,
    String? instructions,
    required int displayOrder,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rest/v1/paper_sections'),
      headers: _headers,
      body: jsonEncode({
        'paper_id': paperId,
        'section_name': name,
        'section_code': code,
        'marks': marks,
        'instructions': instructions,
        'display_order': displayOrder,
      }),
    );
    _checkOk(response, 'insert section "$name"');
    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows.first['id'] as String;
  }

  Future<String> insertQuestion({
    required String sectionId,
    required int questionNumber,
    required String questionType,
    required String questionText,
    int? marks,
    String? originalMarkedOption,
    String? verifiedAnswer,
    required String verificationStatus,
    String? explanation,
    required String qualityStatus,
    String? qualityNote,
    required int displayOrder,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rest/v1/questions'),
      headers: _headers,
      body: jsonEncode({
        'paper_section_id': sectionId,
        'question_number': questionNumber,
        'question_type': questionType,
        'question_text': questionText,
        'marks': marks,
        'original_marked_option': originalMarkedOption,
        'verified_answer': verifiedAnswer,
        'verification_status': verificationStatus,
        'explanation': explanation,
        'quality_status': qualityStatus,
        'quality_note': qualityNote,
        'display_order': displayOrder,
      }),
    );
    _checkOk(response, 'insert question #$questionNumber');
    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows.first['id'] as String;
  }

  Future<void> insertOption({
    required String questionId,
    required String label,
    required String text,
    required bool isVerifiedCorrect,
    required int displayOrder,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rest/v1/question_options'),
      headers: _headers,
      body: jsonEncode({
        'question_id': questionId,
        'option_label': label,
        'option_text': text,
        'is_verified_correct': isVerifiedCorrect,
        'display_order': displayOrder,
      }),
    );
    _checkOk(response, 'insert option "$label"');
  }

  void _checkOk(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw Exception('Failed to $action: ${response.statusCode} ${response.body}');
  }
}
