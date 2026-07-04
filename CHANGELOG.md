## 0.2.2

- Enabled `WINHTTP_OPTION_IPV6_FAST_FALLBACK` (Happy Eyeballs) on the session
  so dual-stack hosts with an unreachable IPv6 route fall back to IPv4 within
  milliseconds instead of stalling until the IPv6 connect times out
  (Windows 10 2004+, silent fallback on older versions).

## 0.2.1

- Fixed async request error reporting so WinHTTP-owned callback pointers are
  not read after `NativeCallable.listener` dispatch.
- Request failures now report safe inferred DNS, connection, response, and TLS
  messages instead of bogus native error codes from stale callback memory.

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
