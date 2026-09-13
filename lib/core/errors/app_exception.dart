/// A user-facing exception. Never expose raw stack traces or backend
/// error text to end users — map everything to one of these.
class AppException implements Exception {
  final String message;
  final AppErrorType type;
  final Object? cause;

  const AppException(this.message, {this.type = AppErrorType.unknown, this.cause});

  factory AppException.network() => const AppException(
        'No internet connection. Please check your network and try again.',
        type: AppErrorType.network,
      );

  factory AppException.server() => const AppException(
        'Server is temporarily unavailable. Please try again shortly.',
        type: AppErrorType.server,
      );

  factory AppException.auth(String message) =>
      AppException(message, type: AppErrorType.auth);

  factory AppException.notFound(String what) =>
      AppException('$what could not be found.', type: AppErrorType.notFound);

  factory AppException.sessionExpired() => const AppException(
        'Your session has expired. Please log in again.',
        type: AppErrorType.sessionExpired,
      );

  @override
  String toString() => message;
}

enum AppErrorType {
  network,
  server,
  auth,
  notFound,
  sessionExpired,
  validation,
  unknown,
}
