A Windows HTTP client for [`package:http`][package:http Client] using the
native [WinHTTP][] API.

## Motivation

Using [WinHTTP][], rather than the socket-based
[`dart:io` HttpClient][dart:io HttpClient] implementation, has several
advantages:

1. It automatically supports Windows system proxy settings (WPAD, PAC scripts).
2. It uses the Windows TLS stack (Schannel) with system certificate stores.
3. It supports automatic gzip/deflate decompression.
4. It integrates with Windows network diagnostics and logging.

## Requirements

- **Windows 8.1 or later** (required for automatic proxy detection and
  decompression)
- **Dart SDK 3.4+**

## Using

The easiest way to use this library is via the high-level interface
defined by [`package:http` Client][package:http Client].

This approach allows the same HTTP code to be used on all platforms, while
still allowing platform-specific setup.

```dart
import 'dart:io';

import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:win_http/win_http.dart';

void main() async {
  final Client httpClient;
  if (Platform.isWindows) {
    httpClient = WinHttpClient.defaultConfiguration();
  } else {
    httpClient = IOClient();
  }

  final response = await httpClient.get(
    Uri.https('www.googleapis.com', '/books/v1/volumes', {'q': 'dart'}),
  );
  print('Status: ${response.statusCode}');
  httpClient.close();
}
```

### Configuration

Use `WinHttpClient.fromConfiguration` for custom settings:

```dart
final client = WinHttpClient.fromConfiguration(
  WinHttpClientConfiguration(
    userAgent: 'MyApp/1.0',
    connectTimeout: Duration(seconds: 10),
    receiveTimeout: Duration(seconds: 30),
  ),
);
```

### Proxy configuration

By default, `WinHttpClient` uses automatic proxy detection
(`WinHttpAccessType.automatic`). You can configure a named proxy:

```dart
final client = WinHttpClient.fromConfiguration(
  WinHttpClientConfiguration(
    accessType: WinHttpAccessType.named,
    proxy: 'proxy.example.com:8080',
    proxyBypass: 'localhost;*.local',
  ),
);
```

Or disable the proxy entirely:

```dart
final client = WinHttpClient.fromConfiguration(
  WinHttpClientConfiguration(
    accessType: WinHttpAccessType.noProxy,
  ),
);
```

## Supported features

| Feature | Status |
|---|---|
| HTTP/HTTPS | Supported |
| GET, POST, PUT, PATCH, DELETE, HEAD | Supported |
| Request headers | Supported |
| Response streaming | Supported |
| Redirect following | Supported (configurable) |
| Gzip/deflate decompression | Automatic |
| System proxy (WPAD/PAC) | Automatic |
| TLS via Windows Schannel | Automatic |
| Cookies | Per-request only (no cross-request cookie jar) |
| Abort/cancel | Partial (response-stream abort works; pre-send abort requires async WinHTTP) |
| Streaming request body | Not supported (body materialized in memory) |

## Known limitations

- **Request bodies are buffered in memory.** The entire request body is
  materialized before sending, similar to [`cronet_http`][cronet_http]. This is
  fine for typical API payloads but not ideal for multi-GB uploads.

- **Headers persist across redirects.** WinHTTP transfers request headers
  (including `Authorization`) across redirect hops. Be cautious with
  sensitive headers when following redirects to untrusted domains.

- **Folded headers.** WinHTTP handles RFC 2822 folded headers internally
  but normalizes whitespace differently than some clients expect.

[WinHTTP]: https://learn.microsoft.com/en-us/windows/win32/winhttp/about-winhttp
[dart:io HttpClient]: https://api.dart.dev/stable/dart-io/HttpClient-class.html
[package:http Client]: https://pub.dev/documentation/http/latest/http/Client-class.html
[cronet_http]: https://pub.dev/packages/cronet_http
