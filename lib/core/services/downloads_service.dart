import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../data/models/download_record.dart';
import '../../data/models/paper.dart';
import '../../data/models/paper_section.dart';
import '../../data/models/question.dart';
import '../errors/app_exception.dart';
import 'cache_service.dart';
import 'pdf_export_service.dart';

/// Persists generated/original PDFs to local app storage and keeps a
/// small index of what's been downloaded, for the Downloads screen.
///
/// Never a separate authorization path: every document saved here is
/// built from data the caller already legitimately fetched under RLS
/// (a generated PDF from already-loaded [Question]s) or from a
/// PUBLISHED paper's own `source_file_url` (itself only ever populated
/// and only ever readable for a published paper) — this service holds
/// no Supabase credentials and makes no authorization decision of its
/// own; see docs/SECURITY_AUDIT.md "Download security".
class DownloadsService {
  DownloadsService._();

  static const _cacheKey = 'cache_download_records';

  static Future<Directory> _downloadsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static List<DownloadRecord> getAll() {
    final records = CacheService.getJson<List<DownloadRecord>>(
      _cacheKey,
      (decoded) =>
          (decoded as List).map((e) => DownloadRecord.fromJson(e as Map<String, dynamic>)).toList(),
    );
    final list = records ?? <DownloadRecord>[];
    list.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return list;
  }

  /// Inserts [record], replacing any existing record with the same [id]
  /// — a paper has at most one saved file per document type, so
  /// downloading it again overwrites in place instead of accumulating
  /// duplicate entries. Exposed separately from the I/O in [_saveBytes]
  /// so this de-duplication rule is unit-testable without touching the
  /// filesystem or SharedPreferences.
  static List<DownloadRecord> upsert(List<DownloadRecord> records, DownloadRecord record) {
    return [record, ...records.where((r) => r.id != record.id)];
  }

  static Future<void> _persist(List<DownloadRecord> records) async {
    await CacheService.setJson(_cacheKey, records.map((r) => r.toJson()).toList());
  }

  static Future<DownloadRecord> _saveBytes({
    required Uint8List bytes,
    required String paperId,
    required DownloadDocumentType documentType,
    required String paperTitle,
    required String phaseName,
    required String subjectName,
    required String contentStatus,
    required String fileName,
  }) async {
    final dir = await _downloadsDir();
    final file = File('${dir.path}/${paperId}_${documentType.dbValue}_$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final record = DownloadRecord(
      paperId: paperId,
      documentType: documentType,
      paperTitle: paperTitle,
      phaseName: phaseName,
      subjectName: subjectName,
      filePath: file.path,
      fileSizeBytes: bytes.length,
      downloadedAt: DateTime.now(),
      contentStatus: contentStatus,
    );
    await _persist(upsert(getAll(), record));
    return record;
  }

  /// Saves one of the app's own generated PDFs (MCQ answer key, solved
  /// short/long questions, complete solved paper) using the exact same
  /// `PdfExportService.buildBytes` the ephemeral Share action uses.
  static Future<DownloadRecord> downloadGeneratedPdf({
    required Paper paper,
    required String phaseName,
    required String subjectName,
    required DownloadDocumentType documentType,
    required String documentTitle,
    required List<({PaperSection section, List<Question> questions})> sections,
  }) async {
    final bytes = await PdfExportService.buildBytes(
      paper: paper,
      phaseName: phaseName,
      subjectName: subjectName,
      documentTitle: documentTitle,
      sections: sections,
    );
    return _saveBytes(
      bytes: bytes,
      paperId: paper.id,
      documentType: documentType,
      paperTitle: paper.title,
      phaseName: phaseName,
      subjectName: subjectName,
      contentStatus: paper.contentStatus,
      fileName: PdfExportService.fileNameFor(paper, documentTitle),
    );
  }

  /// Downloads a PUBLISHED paper's own original source file (from its
  /// public Storage URL — see the class doc comment on why this is
  /// never a separate authorization path). Plain `dart:io` `HttpClient`,
  /// the same fetch mechanism already used by the original-paper viewer
  /// screen — no new HTTP dependency, no Supabase client involved.
  static Future<DownloadRecord> downloadOriginalPaper({
    required Paper paper,
    required String phaseName,
    required String subjectName,
  }) async {
    final url = paper.sourceFileUrl;
    if (url == null || url.isEmpty) {
      throw const AppException('No original source file is available for this paper yet.');
    }
    final bytes = await _fetchUrlBytes(url);
    final extension = (paper.sourceFileType ?? '').toLowerCase().contains('pdf') ||
            url.toLowerCase().endsWith('.pdf')
        ? 'pdf'
        : (url.split('.').last.split('?').first);
    final fileName = '${paper.title}_Original.$extension'.replaceAll(RegExp(r'[^\w.]'), '_');
    return _saveBytes(
      bytes: bytes,
      paperId: paper.id,
      documentType: DownloadDocumentType.originalPaper,
      paperTitle: paper.title,
      phaseName: phaseName,
      subjectName: subjectName,
      contentStatus: paper.contentStatus,
      fileName: fileName,
    );
  }

  static Future<Uint8List> _fetchUrlBytes(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  static bool fileExists(DownloadRecord record) => File(record.filePath).existsSync();

  static Future<Uint8List> readBytes(DownloadRecord record) => File(record.filePath).readAsBytes();

  static Future<void> delete(DownloadRecord record) async {
    final file = File(record.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    await _persist(getAll().where((r) => r.id != record.id).toList());
  }

  /// Deletes every downloaded file and clears the index — used on account
  /// deletion (see AuthRepository.deleteAccount) so no locally-saved file
  /// remains tied to an account that no longer exists.
  static Future<void> clearAll() async {
    for (final record in getAll()) {
      final file = File(record.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _persist(const []);
  }

  /// Human-readable size ("128 KB", "3.4 MB") — pure formatting, no I/O.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
