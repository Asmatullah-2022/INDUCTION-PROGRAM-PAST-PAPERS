import 'dart:async';

/// Debounces rapid calls (e.g. search-as-you-type) so we don't flood the
/// database with a query per keystroke.
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
