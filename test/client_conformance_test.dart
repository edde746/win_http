@TestOn('windows')
library;

import 'package:http_client_conformance_tests/http_client_conformance_tests.dart';
import 'package:test/test.dart';
import 'package:win_http/win_http.dart';

void main() {
  group('WinHttpClient default configuration', () {
    testAll(
      WinHttpClient.defaultConfiguration,
      canStreamRequestBody: false,
      canStreamResponseBody: true,
      preservesMethodCase: false,
      canReceiveSetCookieHeaders: true,
      canSendCookieHeaders: true,
      supportsFoldedHeaders: false, // WinHTTP unfolds headers internally
      supportsAbort: true,
    );
  });

  group('WinHttpClient custom configuration', () {
    testAll(
      () => WinHttpClient.fromConfiguration(
        const WinHttpClientConfiguration(userAgent: 'TestAgent/1.0'),
      ),
      canStreamRequestBody: false,
      canStreamResponseBody: true,
      preservesMethodCase: false,
      canReceiveSetCookieHeaders: true,
      canSendCookieHeaders: true,
      supportsFoldedHeaders: false,
      supportsAbort: true,
    );
  });
}
