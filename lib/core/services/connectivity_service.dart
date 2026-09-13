import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports online/offline status so screens can show cached content with
/// an "Offline content available" indicator instead of a hard error.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Stream<bool> get onStatusChange => _connectivity.onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));
}
