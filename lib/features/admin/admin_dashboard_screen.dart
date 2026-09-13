import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/supabase_service.dart';
import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';

/// Content QA dashboard (spec section 60): shows how many of the 24
/// expected phase/subject paper slots are actually published, broken
/// down by phase, plus question-type and quality-status counts across
/// all published content. Real content import/review screens are listed
/// as admin destinations but intentionally out of scope for this first
/// release — see CLAUDE.md "Admin System" for the rollout plan.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Admin — Content QA Dashboard')),
        body: FutureBuilder(
          future: _loadStats(ref),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              if (snapshot.hasError) {
                return ErrorState(message: snapshot.error.toString());
              }
              return const LoadingList();
            }
            final stats = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Papers Published',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          '${stats.publishedPapers} / ${AppConstants.totalExpectedPapers} expected',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        ...stats.publishedByPhase.entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text('${e.key}: ${e.value}/8'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Question Counts', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('MCQs: ${stats.mcqCount}'),
                        Text('Short: ${stats.shortCount}'),
                        Text('Long: ${stats.longCount}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quality Status', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Verified: ${stats.verifiedCount}'),
                        Text('Questionable: ${stats.questionableCount}'),
                        Text('OCR Uncertain: ${stats.ocrUncertainCount}'),
                        Text('Paper Error: ${stats.paperErrorCount}'),
                        Text('Answer Uncertain: ${stats.answerUncertainCount}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Manage Papers'),
                        subtitle: const Text('Create papers, upload originals, edit sections/questions'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/admin/papers'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.rule_folder_outlined),
                        title: const Text('Review Questionable Questions'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/admin/review'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<_AdminStats> _loadStats(WidgetRef ref) => _AdminStats.fetch();
}

class _AdminStats {
  final int publishedPapers;
  final Map<String, int> publishedByPhase;
  final int mcqCount;
  final int shortCount;
  final int longCount;
  final int verifiedCount;
  final int questionableCount;
  final int ocrUncertainCount;
  final int paperErrorCount;
  final int answerUncertainCount;

  const _AdminStats({
    required this.publishedPapers,
    required this.publishedByPhase,
    required this.mcqCount,
    required this.shortCount,
    required this.longCount,
    required this.verifiedCount,
    required this.questionableCount,
    required this.ocrUncertainCount,
    required this.paperErrorCount,
    required this.answerUncertainCount,
  });

  static Future<_AdminStats> fetch() async {
    final client = SupabaseService.client;

    final publishedPapersRows = await client
        .from('papers')
        .select('id, phase_id, phases(name)')
        .eq('content_status', 'PUBLISHED');

    final publishedByPhase = <String, int>{
      for (final name in AppConstants.phaseNames.values) name: 0,
    };
    for (final row in publishedPapersRows) {
      final phase = row['phases'] as Map<String, dynamic>?;
      final name = phase?['name'] as String?;
      if (name != null && publishedByPhase.containsKey(name)) {
        publishedByPhase[name] = publishedByPhase[name]! + 1;
      }
    }

    final questionRows = await client
        .from('questions')
        .select('question_type, quality_status, paper_sections!inner(papers!inner(content_status))')
        .eq('paper_sections.papers.content_status', 'PUBLISHED');

    var mcq = 0, short = 0, long = 0;
    var verified = 0, questionable = 0, ocrUncertain = 0, paperError = 0, answerUncertain = 0;
    for (final row in questionRows) {
      switch (row['question_type']) {
        case 'mcq':
          mcq++;
          break;
        case 'short':
          short++;
          break;
        case 'long':
          long++;
          break;
      }
      switch (row['quality_status']) {
        case 'VERIFIED':
          verified++;
          break;
        case 'QUESTIONABLE':
          questionable++;
          break;
        case 'OCR_UNCERTAIN':
          ocrUncertain++;
          break;
        case 'PAPER_ERROR':
          paperError++;
          break;
        case 'ANSWER_UNCERTAIN':
          answerUncertain++;
          break;
      }
    }

    return _AdminStats(
      publishedPapers: publishedPapersRows.length,
      publishedByPhase: publishedByPhase,
      mcqCount: mcq,
      shortCount: short,
      longCount: long,
      verifiedCount: verified,
      questionableCount: questionable,
      ocrUncertainCount: ocrUncertain,
      paperErrorCount: paperError,
      answerUncertainCount: answerUncertain,
    );
  }
}
