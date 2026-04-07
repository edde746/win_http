/// A Windows HTTP client for `package:http` using the WinHTTP API.
///
/// Provides [WinHttpClient], a [Client] implementation that uses the native
/// Windows WinHTTP stack for HTTP requests. Requires Windows 8.1+.
///
/// ```dart
/// import 'package:win_http/win_http.dart';
///
/// void main() async {
///   final client = WinHttpClient.defaultConfiguration();
///   try {
///     final response = await client.get(Uri.parse('https://example.com'));
///     print(response.body);
///   } finally {
///     client.close();
///   }
/// }
/// ```
library;

export 'src/win_http_client.dart'
    show WinHttpClient, WinHttpClientConfiguration, WinHttpAccessType;
export 'src/win_http_exception.dart' show WinHttpException;
