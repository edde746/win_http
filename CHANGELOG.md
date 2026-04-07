## 0.1.0

- Initial release.
- `WinHttpClient` implementing `package:http` `BaseClient` via WinHTTP FFI.
- Automatic proxy detection (`WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY`).
- Configurable timeouts, user agent, and proxy settings.
- Automatic gzip/deflate decompression (Windows 8.1+).
- Response body streaming via isolate workers.
- Passes `http_client_conformance_tests` suite (172/172 non-skipped tests).
