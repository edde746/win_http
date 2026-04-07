import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi/winhttp_bindings.dart';
import 'ffi/winhttp_constants.dart';
import 'native_memory.dart';
import 'string_utils.dart';
// callBool, callHandle, callWithError are imported via win_http_exception.dart
import 'win_http_exception.dart';

const _readBufferSize = 8 * 1024;
final _digitRegex = RegExp(r'^\d+$');

/// Data sent to the worker isolate to execute an HTTP request.
class WorkerRequest {
  final int hSession;
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Uint8List body;
  final bool followRedirects;
  final int maxRedirects;
  final SendPort responseSendPort;

  WorkerRequest({
    required this.hSession,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
    required this.followRedirects,
    required this.maxRedirects,
    required this.responseSendPort,
  });
}

/// Response metadata sent back from the worker isolate.
class RawResponseHeaders {
  final int statusCode;
  final String? reasonPhrase;
  final Map<String, String> headers;
  final int? contentLength;
  final Uri finalUrl;

  RawResponseHeaders({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.contentLength,
    required this.finalUrl,
  });
}

/// Error sent back from the worker isolate.
class WinHttpWorkerError {
  final String message;
  WinHttpWorkerError(this.message);
}

/// Worker isolate entry point. Runs synchronous WinHTTP calls.
///
/// Communication protocol via [SendPort]:
/// 1. First message: [RawResponseHeaders] (response metadata)
/// 2. Subsequent messages: [Uint8List] (body chunks)
/// 3. Final message: `null` (body complete)
/// On error: [WinHttpWorkerError]
void workerEntryPoint(WorkerRequest req) {
  var hConnect = 0;
  var hRequest = 0;

  try {
    final host = req.url.host;
    final port = req.url.hasPort
        ? req.url.port
        : (req.url.scheme == 'https'
            ? INTERNET_DEFAULT_HTTPS_PORT
            : INTERNET_DEFAULT_HTTP_PORT);
    final isSecure = req.url.scheme == 'https';

    hConnect = withWideString(
      host,
      (pHost) => callWinHttp(
        'WinHttpConnect',
        () => WinHttpConnect(req.hSession, pHost, port, 0),
      ),
    );

    var objectName = req.url.path;
    if (objectName.isEmpty) objectName = '/';
    if (req.url.hasQuery) objectName = '$objectName?${req.url.query}';

    hRequest = withWideStrings(
      [req.method, objectName],
      (ptrs) => callWinHttp(
        'WinHttpOpenRequest',
        () => WinHttpOpenRequest(
          hConnect,
          ptrs[0],
          ptrs[1],
          nullptr,
          nullptr,
          nullptr,
          isSecure ? WINHTTP_FLAG_SECURE : 0,
        ),
      ),
    );

    // WINHTTP_OPTION_REDIRECT_POLICY is session-level only;
    // use WINHTTP_OPTION_DISABLE_FEATURE on the request handle instead.
    if (!req.followRedirects) {
      setDwordOption(
        hRequest,
        WINHTTP_OPTION_DISABLE_FEATURE,
        WINHTTP_DISABLE_REDIRECTS,
      );
    } else {
      setDwordOption(
        hRequest,
        WINHTTP_OPTION_MAX_HTTP_AUTOMATIC_REDIRECTS,
        req.maxRedirects,
      );
    }

    // Disable automatic cookies to avoid hidden cross-request state.
    setDwordOption(
      hRequest,
      WINHTTP_OPTION_DISABLE_FEATURE,
      WINHTTP_DISABLE_COOKIES,
    );

    // Enable automatic decompression (Windows 8.1+, fails silently on older).
    _trySetOption(
      hRequest,
      WINHTTP_OPTION_DECOMPRESSION,
      WINHTTP_DECOMPRESSION_FLAG_ALL,
    );

    // Batch all headers into a single string for one FFI call.
    if (req.headers.isNotEmpty) {
      final headerBuf = StringBuffer();
      for (final entry in req.headers.entries) {
        headerBuf.write('${entry.key}: ${entry.value}\r\n');
      }
      final headerStr = headerBuf.toString();
      // ADD | REPLACE so we can override WinHTTP default headers.
      withWideString(headerStr, (pHeaders) {
        WinHttpAddRequestHeaders(
          hRequest,
          pHeaders,
          headerStr.length,
          WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE,
        );
      });
    }

    // Send request. Allocate body buffer only if non-empty.
    final bodyLen = req.body.length;
    final pBody =
        bodyLen > 0 ? calloc<Uint8>(bodyLen) : Pointer<Uint8>.fromAddress(0);
    try {
      if (bodyLen > 0) {
        pBody.asTypedList(bodyLen).setAll(0, req.body);
      }
      callWinHttp(
        'WinHttpSendRequest',
        () => WinHttpSendRequest(
          hRequest,
          nullptr,
          0,
          bodyLen > 0 ? pBody.cast() : nullptr,
          bodyLen,
          bodyLen,
          0,
        ),
      );
    } finally {
      if (bodyLen > 0) calloc.free(pBody);
    }

    callWinHttp(
      'WinHttpReceiveResponse',
      () => WinHttpReceiveResponse(hRequest, nullptr),
    );

    final statusCode = queryHeaderInt(
      hRequest,
      WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
    );
    final reasonPhrase = queryHeaderString(hRequest, WINHTTP_QUERY_STATUS_TEXT);
    final rawHeaders =
        queryHeaderString(hRequest, WINHTTP_QUERY_RAW_HEADERS_CRLF);
    final headers = _parseRawHeaders(rawHeaders ?? '');
    final finalUrlStr = queryOptionString(hRequest, WINHTTP_OPTION_URL);
    final finalUrl =
        finalUrlStr != null ? Uri.parse(finalUrlStr) : req.url;

    int? contentLength;
    final clHeader = headers['content-length'];
    if (clHeader != null) {
      if (!_digitRegex.hasMatch(clHeader)) {
        req.responseSendPort.send(
            WinHttpWorkerError('Invalid content-length header [$clHeader].'));
        return;
      }
      contentLength = int.parse(clHeader);
    }

    req.responseSendPort.send(RawResponseHeaders(
      statusCode: statusCode,
      reasonPhrase: reasonPhrase,
      headers: headers,
      contentLength: contentLength,
      finalUrl: finalUrl,
    ));

    var totalBytesRead = 0;
    final pBytesAvailable = calloc<Uint32>();
    final pBytesRead = calloc<Uint32>();
    final pBuffer = calloc<Uint8>(_readBufferSize);
    try {
      while (true) {
        callWinHttp(
          'WinHttpQueryDataAvailable',
          () => WinHttpQueryDataAvailable(hRequest, pBytesAvailable),
        );

        if (pBytesAvailable.value == 0) break;

        final toRead = pBytesAvailable.value < _readBufferSize
            ? pBytesAvailable.value
            : _readBufferSize;

        callWinHttp(
          'WinHttpReadData',
          () => WinHttpReadData(hRequest, pBuffer.cast(), toRead, pBytesRead),
        );

        final bytesRead = pBytesRead.value;
        if (bytesRead == 0) break;

        totalBytesRead += bytesRead;
        req.responseSendPort.send(
          Uint8List.fromList(pBuffer.asTypedList(bytesRead)),
        );
      }
    } finally {
      calloc.free(pBytesAvailable);
      calloc.free(pBytesRead);
      calloc.free(pBuffer);
    }

    // WinHTTP silently accepts mismatched content-length, but package:http
    // expects a ClientException.
    if (contentLength != null && totalBytesRead < contentLength) {
      req.responseSendPort.send(WinHttpWorkerError(
          'Connection closed while receiving data'));
      return;
    }

    req.responseSendPort.send(null);
  } on WinHttpException catch (e) {
    // Map specific WinHTTP errors to the messages expected by package:http.
    if (e.errorCode == ERROR_WINHTTP_REDIRECT_FAILED) {
      req.responseSendPort.send(WinHttpWorkerError('Redirect limit exceeded'));
    } else if (e.errorCode == ERROR_WINHTTP_NAME_NOT_RESOLVED) {
      req.responseSendPort
          .send(WinHttpWorkerError('Could not resolve host'));
    } else if (e.errorCode == ERROR_WINHTTP_CANNOT_CONNECT) {
      req.responseSendPort
          .send(WinHttpWorkerError('Connection refused'));
    } else if (e.errorCode == ERROR_WINHTTP_TIMEOUT) {
      req.responseSendPort.send(WinHttpWorkerError('Connection timed out'));
    } else {
      req.responseSendPort.send(WinHttpWorkerError(e.toString()));
    }
  } on Exception catch (e) {
    req.responseSendPort.send(WinHttpWorkerError(e.toString()));
  } finally {
    if (hRequest != 0) WinHttpCloseHandle(hRequest);
    if (hConnect != 0) WinHttpCloseHandle(hConnect);
  }
}

/// Sets a DWORD option on a WinHTTP handle, ignoring failures.
///
/// Some options may not be supported on all Windows versions or handle types.
/// Returns true if the option was set successfully.
bool _trySetOption(int hInternet, int option, int value) {
  try {
    setDwordOption(hInternet, option, value);
    return true;
  } on WinHttpException {
    return false;
  }
}

/// Parses raw CRLF-delimited headers into a map with lowercase keys.
///
/// Handles:
/// - Folded headers (continuation lines starting with SP/HT per RFC 2822)
/// - Duplicate headers (comma-joined, including set-cookie)
/// - Skips the status line (first line)
Map<String, String> _parseRawHeaders(String rawHeaders) {
  final headers = <String, String>{};
  final lines = rawHeaders.split('\r\n');

  // Skip the status line (e.g., "HTTP/1.1 200 OK").
  var startIndex = 0;
  if (lines.isNotEmpty && lines[0].startsWith('HTTP/')) {
    startIndex = 1;
  }

  // First pass: unfold continuation lines (RFC 2822).
  // WinHTTP may already unfold headers, but we handle it to be safe.
  final unfolded = <String>[];
  for (var i = startIndex; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;

    // Continuation line: starts with space or tab.
    if ((line.startsWith(' ') || line.startsWith('\t')) &&
        unfolded.isNotEmpty) {
      // Replace the leading whitespace with a single space.
      unfolded[unfolded.length - 1] =
          '${unfolded[unfolded.length - 1]} ${line.trimLeft()}';
    } else {
      unfolded.add(line);
    }
  }

  // Second pass: parse name:value pairs.
  for (final line in unfolded) {
    final colonIndex = line.indexOf(':');
    if (colonIndex < 1) continue;

    final name = line.substring(0, colonIndex).trim().toLowerCase();
    final value = line.substring(colonIndex + 1).trim();

    if (headers.containsKey(name)) {
      // Comma-join duplicates — including set-cookie, as the conformance
      // tests expect a single comma-joined string.
      headers[name] = '${headers[name]}, $value';
    } else {
      headers[name] = value;
    }
  }

  return headers;
}
