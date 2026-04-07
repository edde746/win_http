import 'ffi/winhttp_bindings.dart';
import 'ffi/winhttp_constants.dart';

/// Exception thrown when a WinHTTP function fails.
class WinHttpException implements Exception {
  /// The Windows error code from GetLastError().
  final int errorCode;

  /// The WinHTTP function that failed.
  final String function;

  /// Human-readable description of the error.
  final String message;

  WinHttpException(this.errorCode, this.function)
      : message = _errorMessage(errorCode);

  @override
  String toString() =>
      'WinHttpException: $function failed with error $errorCode '
      '(0x${errorCode.toRadixString(16)}): $message';

  static String _errorMessage(int code) => switch (code) {
        ERROR_WINHTTP_TIMEOUT => 'The operation timed out',
        ERROR_WINHTTP_NAME_NOT_RESOLVED =>
          'The server name could not be resolved',
        ERROR_WINHTTP_CANNOT_CONNECT => 'Could not connect to the server',
        ERROR_WINHTTP_CONNECTION_ERROR =>
          'The connection with the server was reset or terminated',
        ERROR_WINHTTP_RESEND_REQUEST => 'The request needs to be resent',
        ERROR_WINHTTP_SECURE_FAILURE =>
          'A security error occurred (certificate validation)',
        ERROR_WINHTTP_REDIRECT_FAILED => 'The redirect failed',
        ERROR_WINHTTP_HEADER_NOT_FOUND => 'The requested header was not found',
        ERROR_INSUFFICIENT_BUFFER => 'The supplied buffer is too small',
        _ => 'WinHTTP error $code (0x${code.toRadixString(16)})',
      };
}

/// Calls a WinHTTP function, capturing GetLastError immediately after
/// to avoid the Dart VM resetting it.
///
/// Throws [WinHttpException] if the result is 0 (FALSE/NULL).
/// Returns the result for handle-returning functions.
int callWinHttp(String functionName, int Function() call) {
  SetLastError(0);
  final result = call();
  final lastError = GetLastError();
  if (result == 0) {
    throw WinHttpException(lastError, functionName);
  }
  return result;
}
