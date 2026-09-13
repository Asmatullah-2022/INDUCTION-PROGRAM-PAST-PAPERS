import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/models/paper.dart';
import '../../data/models/paper_section.dart';
import '../../data/models/question.dart';
import '../constants/app_constants.dart';

/// Generates a PDF from already-verified/published content the app is
/// already displaying on-screen — it never invents metadata. Every field
/// on the generated cover (phase, subject, paper title, verification
/// status, generated date) comes straight from the [Paper]/[Question]
/// models; a field the source data doesn't have (e.g. no total_marks) is
/// simply omitted rather than guessed.
class PdfExportService {
  PdfExportService._();

  static Future<void> shareDocument({
    required Paper paper,
    required String phaseName,
    required String subjectName,
    required String documentTitle,
    required List<({PaperSection section, List<Question> questions})> sections,
  }) async {
    final doc = pw.Document();
    final generatedAt = DateFormat('MMM d, yyyy • HH:mm').format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(AppConstants.appName,
              style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(documentTitle,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('$phaseName • $subjectName'),
          pw.Text(paper.title),
          if (paper.totalMarks != null) pw.Text('Total Marks: ${paper.totalMarks}'),
          if (paper.durationMinutes != null)
            pw.Text('Duration: ${paper.durationMinutes} minutes'),
          pw.Text('Verification status: ${paper.contentStatus}'),
          pw.Text('Generated: $generatedAt',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.Divider(height: 20),
          for (final entry in sections) ..._buildSection(entry.section, entry.questions),
        ],
      ),
    );

    final bytes = await doc.save();
    final fileName =
        '${paper.title}_${documentTitle.replaceAll(' ', '_')}.pdf'.replaceAll(RegExp(r'[^\w.]'), '_');
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static List<pw.Widget> _buildSection(PaperSection section, List<Question> questions) {
    final widgets = <pw.Widget>[
      pw.Text(
        '${section.sectionName}${section.marks != null ? " (${section.marks} marks)" : ""}',
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 8),
    ];

    for (final q in questions) {
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Q${q.questionNumber}. ${q.questionText}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            if (q.qualityStatus.dbValue != 'VERIFIED')
              pw.Text('Quality check: ${q.qualityStatus.label}',
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.orange800)),
            pw.SizedBox(height: 4),
            if (q.options.isNotEmpty)
              ...q.options.map((o) => pw.Text(
                    '${o.optionLabel}. ${o.optionText}${o.isVerifiedCorrect ? "  ✓" : ""}',
                    style: o.isVerifiedCorrect
                        ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                        : null,
                  )),
            if (q.hasAnswerKeyDiscrepancy) ...[
              pw.SizedBox(height: 2),
              pw.Text('Original marked answer: ${q.originalMarkedOption ?? "-"}',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Verified answer: ${q.verifiedAnswer ?? "-"}',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
            if (q.questionType != QuestionType.mcq && q.verifiedAnswer != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(q.verifiedAnswer!),
            ],
            if (q.explanation != null && q.explanation!.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text('Explanation: ${q.explanation}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ],
          ],
        ),
      ));
    }

    widgets.add(pw.SizedBox(height: 12));
    return widgets;
  }
}
