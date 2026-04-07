@TestOn('windows')
library;

import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:win_http/win_http.dart';

void main() {
  group('WinHttpClient lifecycle', () {
    test('defaultConfiguration creates a working client', () {
      final client = WinHttpClient.defaultConfiguration();
      addTearDown(client.close);
      expect(client, isA<Client>());
    });

    test('fromConfiguration creates a working client', () {
      final client = WinHttpClient.fromConfiguration(
        const WinHttpClientConfiguration(
          userAgent: 'TestAgent/1.0',
          accessType: WinHttpAccessType.automatic,
        ),
      );
      addTearDown(client.close);
      expect(client, isA<Client>());
    });

    test('close prevents further requests', () async {
      final client = WinHttpClient.defaultConfiguration();
      client.close();

      expect(
        () => client.get(Uri.parse('https://example.com')),
        throwsA(isA<ClientException>()),
      );
    });

    test('close can be called multiple times', () {
      final client = WinHttpClient.defaultConfiguration();
      client.close();
      client.close(); // Should not throw.
    });
  });

  group('WinHttpClient HTTP requests', () {
    late HttpServer server;
    late Uri serverUrl;
    late WinHttpClient client;

    setUp(() async {
      server = await HttpServer.bind('localhost', 0);
      serverUrl = Uri.parse('http://localhost:${server.port}');
      client = WinHttpClient.defaultConfiguration();
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    test('GET request', () async {
      server.listen((request) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.text
          ..write('hello')
          ..close();
      });

      final response = await client.get(serverUrl);
      expect(response.statusCode, 200);
      expect(response.body, 'hello');
    });

    test('POST request with body', () async {
      server.listen((request) async {
        final body = await request.cast<List<int>>().transform(systemEncoding.decoder).join();
        request.response
          ..statusCode = 200
          ..write('received: $body')
          ..close();
      });

      final response = await client.post(serverUrl, body: 'test body');
      expect(response.statusCode, 200);
      expect(response.body, 'received: test body');
    });

    test('response headers are lowercase', () async {
      server.listen((request) {
        request.response
          ..statusCode = 200
          ..headers.add('X-Custom-Header', 'custom-value')
          ..write('ok')
          ..close();
      });

      final response = await client.get(serverUrl);
      expect(response.headers['x-custom-header'], 'custom-value');
    });

    test('empty response body', () async {
      server.listen((request) {
        request.response
          ..statusCode = 204
          ..close();
      });

      final response = await client.get(serverUrl);
      expect(response.statusCode, 204);
      expect(response.body, isEmpty);
    });

    test('redirect is followed by default', () async {
      var requestCount = 0;
      server.listen((request) {
        requestCount++;
        if (requestCount == 1) {
          request.response
            ..statusCode = 302
            ..headers.add('location', serverUrl.toString())
            ..close();
        } else {
          request.response
            ..statusCode = 200
            ..write('redirected')
            ..close();
        }
      });

      final response = await client.get(serverUrl);
      expect(response.statusCode, 200);
      expect(response.body, 'redirected');
    });

    test('cookie isolation between requests', () async {
      var requestCount = 0;
      server.listen((request) {
        requestCount++;
        if (requestCount == 1) {
          request.response
            ..statusCode = 200
            ..headers.add('set-cookie', 'session=abc123')
            ..write('first')
            ..close();
        } else {
          // Second request should NOT have the cookie because automatic
          // cookie handling is disabled.
          final hasCookie = request.headers['cookie'] != null;
          request.response
            ..statusCode = 200
            ..write('cookie_present=$hasCookie')
            ..close();
        }
      });

      await client.get(serverUrl);
      final response = await client.get(serverUrl);
      expect(response.body, 'cookie_present=false');
    });
  });
}
