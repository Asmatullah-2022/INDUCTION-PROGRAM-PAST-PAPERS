import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/downloads_service.dart';
import '../../data/models/download_record.dart';

/// Local-only state (no network) — reads DownloadsService's SharedPreferences-
/// backed index. [refresh] is called by the export screens after a
/// successful download so the Downloads screen (if already open in
/// another tab of the navigation stack) reflects it without waiting for
/// a full app restart.
class DownloadsNotifier extends Notifier<List<DownloadRecord>> {
  @override
  List<DownloadRecord> build() => DownloadsService.getAll();

  void refresh() => state = DownloadsService.getAll();

  Future<void> delete(DownloadRecord record) async {
    await DownloadsService.delete(record);
    refresh();
  }
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, List<DownloadRecord>>(
  DownloadsNotifier.new,
);
