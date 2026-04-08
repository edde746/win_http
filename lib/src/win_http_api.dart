import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart';

import 'ffi/winhttp_bindings.dart';
import 'ffi/winhttp_constants.dart';
import 'native_memory.dart';
import 'win_http_exception.dart';

const _readBufferSize = 64 * 1024;
final _digitRegex = RegExp(r'^\d+$');

// ---------------------------------------------------------------------------
// Request lifecycle phases
// ---------------------------------------------------------------------------

enum RequestPhase {
  sendingRequest,
  receivingResponse,
  readingData,
  done,
  error,
}

// ---------------------------------------------------------------------------
// Per-request async state
// ---------------------------------------------------------------------------

/// State for a single in-flight async WinHTTP request.
class AsyncRequestState {
  final int contextId;
  int hRequest;
  int hConnect;
  final BaseRequest request;

  RequestPhase phase = RequestPhase.sendingRequest;

  final Completer<RawResponseHeaders> headersCompleter =
      Completer<RawResponseHeaders>();
  late final StreamController<List<int>> bodyController;

  /// Native buffer for WinHttpReadData — kept alive between calls.
  Pointer<Uint8> readBuffer = nullptr;

  /// Native buffer for request body — kept alive until SENDREQUEST_COMPLETE.
  Pointer<Uint8> bodyBuffer = nullptr;
  int bodyLength = 0;

  int totalBytesRead = 0;
  int? contentLength;
  bool aborted = false;

  /// Callback invoked when the body stream subscription is cancelled.
  void Function()? onStreamCancel;

  AsyncRequestState({
    required this.contextId,
    required this.hRequest,
    required this.hConnect,
    required this.request,
  }) {
    bodyController = StreamController<List<int>>(
      onCancel: () {
        onStreamCancel?.call();
      },
    );
  }

  void freeNativeMemory() {
    if (readBuffer != nullptr) {
      calloc.free(readBuffer);
      readBuffer = nullptr;
    }
    if (bodyBuffer != nullptr) {
      calloc.free(bodyBuffer);
      bodyBuffer = nullptr;
    }
  }
}

// ---------------------------------------------------------------------------
// Response metadata (kept from sync implementation)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Async callback dispatcher — one per session
// ---------------------------------------------------------------------------

class AsyncCallbackDispatcher {
  final Map<int, AsyncRequestState> _requests = {};
  int _nextContextId = 1;

  late final NativeCallable<WinHttpStatusCallbackNative> _nativeCallback;

  AsyncCallbackDispatcher() {
    _nativeCallback = NativeCallable<WinHttpStatusCallbackNative>.listener(
      _onStatusCallback,
    );
  }

  /// The native function pointer to register with WinHttpSetStatusCallback.
  Pointer<NativeFunction<WinHttpStatusCallbackNative>>
      get nativeCallbackPointer => _nativeCallback.nativeFunction;

  /// Allocates a unique context ID for a new request.
  int allocateContextId() => _nextContextId++;

  /// Registers a request state for callback dispatch.
  void registerRequest(int contextId, AsyncRequestState state) {
    _requests[contextId] = state;
  }

  /// Initiates cleanup: frees native memory and closes handles.
  /// The request is removed from the map when HANDLE_CLOSING fires.
  void initiateCleanup(AsyncRequestState state) {
    state.freeNativeMemory();
    if (state.hRequest != 0) {
      WinHttpCloseHandle(state.hRequest);
      state.hRequest = 0;
    }
    if (state.hConnect != 0) {
      WinHttpCloseHandle(state.hConnect);
      state.hConnect = 0;
    }
  }

  /// Closes the native callback. Call after the session handle is closed.
  void close() {
    _nativeCallback.close();
  }

  // -------------------------------------------------------------------------
  // Callback dispatch — runs on the Dart event loop
  // -------------------------------------------------------------------------

  void _onStatusCallback(
    int hInternet,
    int dwContext,
    int dwInternetStatus,
    Pointer<Void> lpvStatusInformation,
    int dwStatusInformationLength,
  ) {
    final state = _requests[dwContext];
    if (state == null || state.aborted) return;

    switch (dwInternetStatus) {
      case WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE:
        _onSendRequestComplete(state);
      case WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE:
        _onHeadersAvailable(state);
      case WINHTTP_CALLBACK_STATUS_DATA_AVAILABLE:
        // If using WinHttpQueryDataAvailable, handle here.
        // Currently unused — we loop directly on WinHttpReadData.
        break;
      case WINHTTP_CALLBACK_STATUS_READ_COMPLETE:
        _onReadComplete(state, dwStatusInformationLength);
      case WINHTTP_CALLBACK_STATUS_REQUEST_ERROR:
        _onRequestError(state, lpvStatusInformation, dwStatusInformationLength);
      case WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING:
        _requests.remove(dwContext);
      // REDIRECT, WRITE_COMPLETE: no action needed
    }
  }

  void _onSendRequestComplete(AsyncRequestState state) {
    // Free the body buffer — WinHTTP has consumed it.
    if (state.bodyBuffer != nullptr) {
      calloc.free(state.bodyBuffer);
      state.bodyBuffer = nullptr;
    }

    // Initiate response reception.
    state.phase = RequestPhase.receivingResponse;
    try {
      callWinHttpAsync(
        'WinHttpReceiveResponse',
        () => WinHttpReceiveResponse(state.hRequest, nullptr),
      );
    } on WinHttpException catch (e) {
      _completeWithError(state, e.message);
    }
  }

  void _onHeadersAvailable(AsyncRequestState state) {
    try {
      final statusCode = queryHeaderInt(
        state.hRequest,
        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      );
      final reasonPhrase =
          queryHeaderString(state.hRequest, WINHTTP_QUERY_STATUS_TEXT);
      final rawHeaders =
          queryHeaderString(state.hRequest, WINHTTP_QUERY_RAW_HEADERS_CRLF);
      final headers = _parseRawHeaders(rawHeaders ?? '');
      final finalUrlStr =
          queryOptionString(state.hRequest, WINHTTP_OPTION_URL);
      final finalUrl = finalUrlStr != null
          ? Uri.parse(finalUrlStr)
          : state.request.url;

      int? contentLength;
      final clHeader = headers['content-length'];
      if (clHeader != null) {
        if (!_digitRegex.hasMatch(clHeader)) {
          _completeWithError(
              state, 'Invalid content-length header [$clHeader].');
          return;
        }
        contentLength = int.parse(clHeader);
      }
      state.contentLength = contentLength;

      state.headersCompleter.complete(RawResponseHeaders(
        statusCode: statusCode,
        reasonPhrase: reasonPhrase,
        headers: headers,
        contentLength: contentLength,
        finalUrl: finalUrl,
      ));

      // Start reading body.
      state.phase = RequestPhase.readingData;
      state.readBuffer = calloc<Uint8>(_readBufferSize);
      _issueRead(state);
    } on WinHttpException catch (e) {
      _completeWithError(state, e.message);
    }
  }

  void _onReadComplete(AsyncRequestState state, int bytesRead) {
    if (bytesRead > 0) {
      state.totalBytesRead += bytesRead;
      // Our readBuffer is safe to dereference — we own it.
      state.bodyController.add(
        Uint8List.fromList(state.readBuffer.asTypedList(bytesRead)),
      );
      _issueRead(state);
    } else {
      // EOF — body is done.
      if (state.contentLength != null &&
          state.totalBytesRead < state.contentLength!) {
        state.bodyController.addError(ClientException(
          'Connection closed while receiving data',
          state.request.url,
        ));
      }
      state.phase = RequestPhase.done;
      state.bodyController.close();
      initiateCleanup(state);
    }
  }

  void _onRequestError(AsyncRequestState state,
      Pointer<Void> lpvStatusInformation, int dwStatusInformationLength) {
    // Best-effort read of WINHTTP_ASYNC_RESULT — the pointer may be dangling
    // since NativeCallable.listener runs asynchronously. In practice it's
    // usually still valid due to timing.
    var errorCode = 0;
    try {
      if (dwStatusInformationLength >= sizeOf<WINHTTP_ASYNC_RESULT>() &&
          lpvStatusInformation != nullptr) {
        final result = lpvStatusInformation.cast<WINHTTP_ASYNC_RESULT>().ref;
        errorCode = result.dwError;
      }
    } catch (_) {
      // Pointer was invalid — use phase-based fallback.
    }

    final message = _errorMessageForCode(errorCode, state.phase);
    _completeWithError(state, message);
  }

  void _issueRead(AsyncRequestState state) {
    try {
      callWinHttpAsync(
        'WinHttpReadData',
        () => WinHttpReadData(
          state.hRequest,
          state.readBuffer.cast(),
          _readBufferSize,
          nullptr, // Ignored in async mode.
        ),
      );
    } on WinHttpException catch (e) {
      _completeWithError(state, e.message);
    }
  }

  void _completeWithError(AsyncRequestState state, String message) {
    state.phase = RequestPhase.error;
    final error = ClientException(message, state.request.url);
    if (!state.headersCompleter.isCompleted) {
      state.headersCompleter.completeError(error);
    } else if (!state.bodyController.isClosed) {
      state.bodyController.addError(error);
      state.bodyController.close();
    }
    initiateCleanup(state);
  }

  static String _errorMessageForCode(int errorCode, RequestPhase phase) {
    if (errorCode != 0) {
      return switch (errorCode) {
        ERROR_WINHTTP_TIMEOUT => 'Connection timed out',
        ERROR_WINHTTP_NAME_NOT_RESOLVED => 'Could not resolve host',
        ERROR_WINHTTP_CANNOT_CONNECT => 'Connection refused',
        ERROR_WINHTTP_REDIRECT_FAILED => 'Redirect limit exceeded',
        ERROR_WINHTTP_CONNECTION_ERROR =>
          'The connection was reset or terminated',
        ERROR_WINHTTP_SECURE_FAILURE => 'TLS certificate validation failed',
        _ => 'WinHTTP error $errorCode (0x${errorCode.toRadixString(16)})',
      };
    }
    return switch (phase) {
      RequestPhase.sendingRequest => 'Failed to send request',
      RequestPhase.receivingResponse => 'Failed to receive response',
      RequestPhase.readingData => 'Connection closed while receiving data',
      _ => 'WinHTTP request failed',
    };
  }
}

// ---------------------------------------------------------------------------
// Helpers (kept from sync implementation)
// ---------------------------------------------------------------------------

/// Sets a DWORD option, ignoring failures (for optional features).
bool trySetOption(int hInternet, int option, int value) {
  try {
    setDwordOption(hInternet, option, value);
    return true;
  } on WinHttpException {
    return false;
  }
}

/// Parses raw CRLF-delimited headers into a map with lowercase keys.
Map<String, String> _parseRawHeaders(String rawHeaders) {
  final headers = <String, String>{};
  final lines = rawHeaders.split('\r\n');

  var startIndex = 0;
  if (lines.isNotEmpty && lines[0].startsWith('HTTP/')) {
    startIndex = 1;
  }

  final unfolded = <String>[];
  for (var i = startIndex; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    if ((line.startsWith(' ') || line.startsWith('\t')) &&
        unfolded.isNotEmpty) {
      unfolded[unfolded.length - 1] =
          '${unfolded[unfolded.length - 1]} ${line.trimLeft()}';
    } else {
      unfolded.add(line);
    }
  }

  for (final line in unfolded) {
    final colonIndex = line.indexOf(':');
    if (colonIndex < 1) continue;
    final name = line.substring(0, colonIndex).trim().toLowerCase();
    final value = line.substring(colonIndex + 1).trim();
    if (headers.containsKey(name)) {
      headers[name] = '${headers[name]}, $value';
    } else {
      headers[name] = value;
    }
  }

  return headers;
}
