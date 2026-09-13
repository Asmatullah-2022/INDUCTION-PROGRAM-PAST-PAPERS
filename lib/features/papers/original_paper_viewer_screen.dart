import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/downloads_service.dart';
import '../../data/models/paper.dart';
import '../../shared/widgets/state_widgets.dart';
import '../downloads/downloads_providers.dart';
import 'papers_providers.dart';

/// Displays the original scanned/source paper exactly as supplied — this
/// file is never modified by the app. Supports PDF (page nav, zoom/pan)
/// and image scans (pinch zoom/pan), plus fullscreen and share.
class OriginalPaperViewerScreen extends ConsumerStatefulWidget {
  final String paperId;
  const OriginalPaperViewerScreen({super.key, required this.paperId});

  @override
  ConsumerState<OriginalPaperViewerScreen> createState() =>
      _OriginalPaperViewerScreenState();
}

class _OriginalPaperViewerScreenState extends ConsumerState<OriginalPaperViewerScreen> {
  PdfControllerPinch? _pdfController;
  bool _fullscreen = false;

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<Uint8List> _fetchBytes(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes = await consolidateHttpResponse(response);
      return bytes;
    } finally {
      client.close();
    }
  }

  Future<Uint8List> consolidateHttpResponse(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Widget build(BuildContext context) {
    final paperAsync = ref.watch(paperByIdProvider(widget.paperId));

    return paperAsync.when(
      data: (paper) {
        final url = paper.sourceFileUrl;
        if (url == null || url.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Original Paper')),
            body: const EmptyState(
              icon: Icons.warning_amber_rounded,
              title: 'MISSING SOURCE PAPER',
              subtitle:
                  'DO NOT PUBLISH — the original scanned paper has not been uploaded yet.',
            ),
          );
        }

        final isPdf = (paper.sourceFileType ?? '').toLowerCase().contains('pdf') ||
            url.toLowerCase().endsWith('.pdf');

        final body = isPdf ? _buildPdfViewer(url) : _buildImageViewer(url);

        if (_fullscreen) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                body,
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _fullscreen = false),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Original Paper'),
            actions: [
              IconButton(
                icon: const Icon(Icons.fullscreen),
                onPressed: () => setState(() => _fullscreen = true),
              ),
              IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Download',
                onPressed: () => _downloadOriginal(paper),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () => Share.shareUri(Uri.parse(url)),
              ),
            ],
          ),
          body: body,
        );
      },
      loading: () => const Scaffold(body: LoadingList(itemCount: 1)),
      error: (e, st) => Scaffold(
        appBar: AppBar(title: const Text('Original Paper')),
        body: ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(paperByIdProvider(widget.paperId)),
        ),
      ),
    );
  }

  Future<void> _downloadOriginal(Paper paper) async {
    final names = await ref.read(paperPhaseSubjectNamesProvider(widget.paperId).future);
    try {
      await DownloadsService.downloadOriginalPaper(
        paper: paper,
        phaseName: names.phaseName,
        subjectName: names.subjectName,
      );
      ref.read(downloadsProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved to Downloads'),
            action: SnackBarAction(label: 'View', onPressed: () => context.push('/downloads')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Widget _buildPdfViewer(String url) {
    _pdfController ??= PdfControllerPinch(document: PdfDocument.openData(_fetchBytes(url)));
    return PdfViewPinch(controller: _pdfController!);
  }

  Widget _buildImageViewer(String url) {
    return PhotoView(
      imageProvider: NetworkImage(url),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3,
      loadingBuilder: (context, event) => const Center(child: CircularProgressIndicator()),
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Text('Failed to load image', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
