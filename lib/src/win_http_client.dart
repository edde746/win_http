import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart';

import 'ffi/winhttp_bindings.dart';
import 'ffi/winhttp_constants.dart';
import 'native_memory.dart';
import 'string_utils.dart';
import 'win_http_api.dart';
import 'win_http_exception.dart';

/// The type of proxy access to use for WinHTTP sessions.
enum WinHttpAccessType {
  /// Direct connection, no proxy.
  noProxy(WINHTTP_ACCESS_TYPE_NO_PROXY),

  /// Use a named proxy server.
  named(WINHTTP_ACCESS_TYPE_NAMED_PROXY),

  /// Use automatic proxy detection (recommended, Windows 8.1+).
  automatic(WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY);

  final int value;
  const WinHttpAccessType(this.value);
}

/// Configuration for a [WinHttpClient] session.
class WinHttpClientConfiguration {
  /// User-Agent string for HTTP requests.
  final String? userAgent;

  /// DNS resolve timeout. Null uses WinHTTP default.
  final Duration? resolveTimeout;

  /// TCP connect timeout. Null uses WinHTTP default.
  final Duration? connectTimeout;

  /// Send timeout. Null uses WinHTTP default.
  final Duration? sendTimeout;

  /// Receive timeout. Null uses WinHTTP default.
  final Duration? receiveTimeout;

  /// Proxy access type. Defaults to [WinHttpAccessType.automatic].
  final WinHttpAccessType accessType;

  /// Proxy server name (e.g., "proxy.example.com:8080").
  ///
  /// Only used when [accessType] is [WinHttpAccessType.named].
  /// This is NOT a URL — WinHTTP expects a server name string.
  final String? proxy;

  /// Semicolon-delimited list of hosts that bypass the proxy.
  ///
  /// Only used when [accessType] is [WinHttpAccessType.named].
  final String? proxyBypass;

  /// Maximum concurrent connections per server.
  ///
  /// WinHTTP defaults to 6 for HTTP/1.1, which can cause failures or
  /// stalls when loading many resources (e.g., image thumbnails) from
  /// the same host. Set higher for apps that make many concurrent requests.
  /// Null uses WinHTTP's default (6).
  final int? maxConnectionsPerServer;

  const WinHttpClientConfiguration({
    this.userAgent,
    this.resolveTimeout,
    this.connectTimeout,
    this.sendTimeout,
    this.receiveTimeout,
    this.accessType = WinHttpAccessType.automatic,
    this.proxy,
    this.proxyBypass,
    this.maxConnectionsPerServer,
  });
}

/// This class can be removed when `package:http` v2 is released.
class _StreamedResponseWithUrl extends StreamedResponse
    implements BaseResponseWithUrl {
  @override
  final Uri url;

  _StreamedResponseWithUrl(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.request,
    super.headers,
    super.isRedirect,
    super.reasonPhrase,
  });
}

/// A HTTP [Client] based on the Windows
/// [WinHTTP](https://learn.microsoft.com/en-us/windows/win32/winhttp/about-winhttp)
/// API.
///
/// Uses async WinHTTP with native callbacks — no isolate spawning overhead.
/// All requests run on the main Dart isolate via `NativeCallable.listener`.
///
/// **Platform**: Windows 8.1+.
///
/// Example:
/// ```dart
/// final client = WinHttpClient.defaultConfiguration();
/// try {
///   final response = await client.get(Uri.parse('https://example.com'));
///   print(response.body);
/// } finally {
///   client.close();
/// }
/// ```
class WinHttpClient extends BaseClient {
  int? _hSession;
  AsyncCallbackDispatcher? _dispatcher;
  int _pendingRequests = 0;
  bool _closePending = false;

  WinHttpClient._(this._hSession, this._dispatcher);

  /// Creates a [WinHttpClient] with default configuration.
  factory WinHttpClient.defaultConfiguration() =>
      WinHttpClient.fromConfiguration(const WinHttpClientConfiguration());

  /// Creates a [WinHttpClient] with the given [config].
  factory WinHttpClient.fromConfiguration(WinHttpClientConfiguration config) {
    final userAgent = config.userAgent ?? 'Dart/win_http';

    final hSession = withWideStrings(
      [userAgent, config.proxy, config.proxyBypass],
      (ptrs) => callWinHttp(
        'WinHttpOpen',
        () => WinHttpOpen(
          ptrs[0],
          config.accessType.value,
          ptrs[1],
          ptrs[2],
          WINHTTP_FLAG_ASYNC,
        ),
      ),
    );

    // Create callback dispatcher and register on the session.
    final dispatcher = AsyncCallbackDispatcher();
    // Subscribe to all notifications — WinHTTP may fire intermediate statuses
    // (RESOLVING_NAME, CONNECTING_TO_SERVER, etc.) that block progress if
    // not subscribed.
    final prevCallback = WinHttpSetStatusCallback(
      hSession,
      dispatcher.nativeCallbackPointer,
      0xFFFFFFFF, // WINHTTP_CALLBACK_FLAG_ALL_NOTIFICATIONS
      0,
    );
    if (prevCallback.address == WINHTTP_INVALID_STATUS_CALLBACK) {
      final err = GetLastError();
      dispatcher.close();
      WinHttpCloseHandle(hSession);
      throw WinHttpException(err, 'WinHttpSetStatusCallback');
    }

    // Enable HTTP/2 for connection multiplexing (Windows 10+, silent fallback).
    trySetOption(hSession, WINHTTP_OPTION_ENABLE_HTTP_PROTOCOL,
        WINHTTP_PROTOCOL_FLAG_HTTP2);

    // Increase max connections per server if configured.
    if (config.maxConnectionsPerServer != null) {
      trySetOption(hSession, WINHTTP_OPTION_MAX_CONNS_PER_SERVER,
          config.maxConnectionsPerServer!);
      trySetOption(hSession, WINHTTP_OPTION_MAX_CONNS_PER_1_0_SERVER,
          config.maxConnectionsPerServer!);
    }

    // Redirect policy is session-level.
    setDwordOption(
      hSession,
      WINHTTP_OPTION_REDIRECT_POLICY,
      WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS,
    );

    if (config.resolveTimeout != null ||
        config.connectTimeout != null ||
        config.sendTimeout != null ||
        config.receiveTimeout != null) {
      try {
        callWinHttp(
          'WinHttpSetTimeouts',
          () => WinHttpSetTimeouts(
            hSession,
            config.resolveTimeout?.inMilliseconds ?? 0,
            config.connectTimeout?.inMilliseconds ?? 60000,
            config.sendTimeout?.inMilliseconds ?? 30000,
            config.receiveTimeout?.inMilliseconds ?? 30000,
          ),
        );
      } on WinHttpException {
        dispatcher.close();
        WinHttpCloseHandle(hSession);
        rethrow;
      }
    }

    return WinHttpClient._(hSession, dispatcher);
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final hSession = _hSession;
    final dispatcher = _dispatcher;
    if (hSession == null || dispatcher == null || _closePending) {
      throw ClientException(
        'HTTP request failed. Client is already closed.',
        request.url,
      );
    }

    _pendingRequests++;

    final stream = request.finalize();
    final body = await stream.toBytes();

    // Open connection and request handles (synchronous in async mode too).
    final host = request.url.host;
    final port = request.url.hasPort
        ? request.url.port
        : (request.url.scheme == 'https'
            ? INTERNET_DEFAULT_HTTPS_PORT
            : INTERNET_DEFAULT_HTTP_PORT);

    int hConnect;
    try {
      hConnect = withWideString(
        host,
        (pHost) => callWinHttp(
          'WinHttpConnect',
          () => WinHttpConnect(hSession, pHost, port, 0),
        ),
      );
    } catch (_) {
      _pendingRequests--;
      rethrow;
    }

    int hRequest;
    try {
      var objectName = request.url.path;
      if (objectName.isEmpty) objectName = '/';
      if (request.url.hasQuery) objectName = '$objectName?${request.url.query}';

      hRequest = withWideStrings(
        [request.method, objectName],
        (ptrs) => callWinHttp(
          'WinHttpOpenRequest',
          () => WinHttpOpenRequest(
            hConnect,
            ptrs[0],
            ptrs[1],
            nullptr,
            nullptr,
            nullptr,
            request.url.scheme == 'https' ? WINHTTP_FLAG_SECURE : 0,
          ),
        ),
      );
    } catch (_) {
      WinHttpCloseHandle(hConnect);
      _pendingRequests--;
      rethrow;
    }

    // Configure request options (synchronous).
    if (!request.followRedirects) {
      setDwordOption(
          hRequest, WINHTTP_OPTION_DISABLE_FEATURE, WINHTTP_DISABLE_REDIRECTS);
    } else {
      setDwordOption(hRequest, WINHTTP_OPTION_MAX_HTTP_AUTOMATIC_REDIRECTS,
          request.maxRedirects);
    }
    setDwordOption(
        hRequest, WINHTTP_OPTION_DISABLE_FEATURE, WINHTTP_DISABLE_COOKIES);
    trySetOption(
        hRequest, WINHTTP_OPTION_DECOMPRESSION, WINHTTP_DECOMPRESSION_FLAG_ALL);

    // Batch headers.
    if (request.headers.isNotEmpty) {
      final headerBuf = StringBuffer();
      for (final entry in request.headers.entries) {
        headerBuf.write('${entry.key}: ${entry.value}\r\n');
      }
      final headerStr = headerBuf.toString();
      withWideString(headerStr, (pHeaders) {
        WinHttpAddRequestHeaders(hRequest, pHeaders, headerStr.length,
            WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
      });
    }

    // Create async request state.
    final contextId = dispatcher.allocateContextId();
    final state = AsyncRequestState(
      contextId: contextId,
      hRequest: hRequest,
      hConnect: hConnect,
      request: request,
    );
    dispatcher.registerRequest(contextId, state);

    // When the consumer cancels the response stream subscription, abort
    // the WinHTTP request by closing the handle.
    state.onStreamCancel = () {
      if (!state.aborted && state.phase == RequestPhase.readingData) {
        state.aborted = true;
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
    };

    // Allocate body buffer — must survive until SENDREQUEST_COMPLETE.
    if (body.isNotEmpty) {
      state.bodyBuffer = calloc<Uint8>(body.length);
      state.bodyBuffer.asTypedList(body.length).setAll(0, body);
      state.bodyLength = body.length;
    }

    // Send request (async — returns immediately).
    try {
      callWinHttpAsync(
        'WinHttpSendRequest',
        () => WinHttpSendRequest(
          hRequest,
          nullptr,
          0,
          body.isNotEmpty ? state.bodyBuffer.cast() : nullptr,
          body.length,
          body.length,
          contextId,
        ),
      );
    } catch (_) {
      dispatcher.initiateCleanup(state);
      _pendingRequests--;
      rethrow;
    }

    // Wire up abort — closing the handle cancels pending async operations.
    if (request case Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.whenComplete(() {
        if (state.aborted) return;
        state.aborted = true;
        final error = RequestAbortedException(request.url);
        if (!state.headersCompleter.isCompleted) {
          state.headersCompleter.completeError(error);
        } else if (!state.bodyController.isClosed) {
          state.bodyController.addError(error);
          state.bodyController.close();
        }
        dispatcher.initiateCleanup(state);
      }));
    }

    // Wait for headers (completes when HEADERS_AVAILABLE fires).
    final RawResponseHeaders rawHeaders;
    try {
      rawHeaders = await state.headersCompleter.future;
    } catch (_) {
      _pendingRequests--;
      unawaited(state.bodyController.close());
      rethrow;
    }

    // Track body stream completion for session lifecycle.
    unawaited(state.bodyController.done.then((_) {
      _pendingRequests--;
      _maybeCloseSession();
    }, onError: (_) {
      _pendingRequests--;
      _maybeCloseSession();
    }));

    final statusCode = rawHeaders.statusCode;
    final isRedirect =
        !request.followRedirects && statusCode >= 300 && statusCode < 400;

    return _StreamedResponseWithUrl(
      state.bodyController.stream,
      rawHeaders.statusCode,
      url: rawHeaders.finalUrl,
      contentLength: rawHeaders.contentLength,
      reasonPhrase: rawHeaders.reasonPhrase,
      request: request,
      isRedirect: isRedirect,
      headers: rawHeaders.headers,
    );
  }

  @override
  void close() {
    _closePending = true;
    _maybeCloseSession();
  }

  void _maybeCloseSession() {
    if (_closePending && _pendingRequests <= 0 && _hSession != null) {
      WinHttpCloseHandle(_hSession!);
      _hSession = null;
      // WinHTTP fires final callbacks (HANDLE_CLOSING) from its thread pool
      // after handles are closed. Delay closing the NativeCallable to let
      // these drain. The callback ignores them (unknown context), but the
      // native function pointer must remain valid.
      final dispatcher = _dispatcher;
      _dispatcher = null;
      Future.delayed(const Duration(seconds: 2), () {
        dispatcher?.close();
      });
    }
  }
}
