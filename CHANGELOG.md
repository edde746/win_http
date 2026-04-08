## 0.2.0

- **Breaking**: Migrated from sync WinHTTP + isolates to async WinHTTP callbacks.
  No public API changes, but internal architecture is completely different.
- Abort support via `WinHttpCloseHandle` (native cancellation).
- HTTP/2 enabled by default (Windows 10+, silent fallback).
- Added `maxConnectionsPerServer` to `WinHttpClientConfiguration`.
- Eliminated per-request isolate spawning overhead.
- 64KB read buffer for better throughput.

## 0.1.0

- Initial release.
- `WinHttpClient` implementing `package:http` `BaseClient` via WinHTTP FFI.
- Automatic proxy detection (`WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY`).
- Configurable timeouts, user agent, and proxy settings.
- Automatic gzip/deflate decompression (Windows 8.1+).
- Response body streaming via isolate workers.
- Passes `http_client_conformance_tests` suite (172/172 non-skipped tests).
