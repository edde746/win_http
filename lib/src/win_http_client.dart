import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

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

  const WinHttpClientConfiguration({
    this.userAgent,
    this.resolveTimeout,
    this.connectTimeout,
    this.sendTimeout,
    this.receiveTimeout,
    this.accessType = WinHttpAccessType.automatic,
    this.proxy,
    this.proxyBypass,
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
/// This client uses synchronous WinHTTP calls on worker isolates to avoid
/// blocking the main isolate's event loop.
///
/// **Platform**: Windows 8.1+ (required for automatic decompression and
/// automatic proxy detection).
///
/// **Limitations**:
/// - Request bodies are materialized in memory before sending (no streaming).
/// - Abort is not supported in v0.1 (synchronous WinHTTP cannot be safely
///   cancelled from another isolate).
/// - Headers added via `WinHttpAddRequestHeaders` are transferred across
///   redirects, which means sensitive headers like `Authorization` could leak
///   on cross-origin redirect hops.
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
  int _pendingRequests = 0;

  WinHttpClient._(this._hSession);

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
          0, // Synchronous mode
        ),
      ),
    );

    // Set redirect policy to ALWAYS on the session handle.
    // Per-request redirect control uses WINHTTP_OPTION_DISABLE_FEATURE.
    setDwordOption(
      hSession,
      WINHTTP_OPTION_REDIRECT_POLICY,
      WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS,
    );

    // Configure timeouts if specified.
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
        WinHttpCloseHandle(hSession);
        rethrow;
      }
    }

    return WinHttpClient._(hSession);
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final hSession = _hSession;
    if (hSession == null || _closePending) {
      throw ClientException(
        'HTTP request failed. Client is already closed.',
        request.url,
      );
    }

    _pendingRequests++;

    final stream = request.finalize();
    final body = await stream.toBytes();

    final responseHeadersCompleter = Completer<RawResponseHeaders>();
    final responseController = StreamController<List<int>>();
    final receivePort = ReceivePort();
    var aborted = false;

    receivePort.listen((message) {
      if (aborted) return; // Discard messages after abort.
      if (message is RawResponseHeaders) {
        responseHeadersCompleter.complete(message);
      } else if (message is Uint8List) {
        responseController.add(message);
      } else if (message == null) {
        responseController.close();
        receivePort.close();
      } else if (message is WinHttpWorkerError) {
        final error = ClientException(message.message, request.url);
        if (!responseHeadersCompleter.isCompleted) {
          responseHeadersCompleter.completeError(error);
        } else {
          responseController.addError(error);
        }
        responseController.close();
        receivePort.close();
      }
    });

    await Isolate.spawn(
      workerEntryPoint,
      WorkerRequest(
        hSession: hSession,
        method: request.method,
        url: request.url,
        headers: request.headers,
        body: body,
        followRedirects: request.followRedirects,
        maxRedirects: request.maxRedirects,
        responseSendPort: receivePort.sendPort,
      ),
    );

    // Handle abort. We can't cancel the WinHTTP call in the worker isolate,
    // but we can inject the error into the stream and close the receive port.
    // The worker isolate will finish its work but the results are discarded.
    if (request case Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.whenComplete(() {
        aborted = true;
        final error = RequestAbortedException(request.url);
        if (!responseHeadersCompleter.isCompleted) {
          responseHeadersCompleter.completeError(error);
        } else if (!responseController.isClosed) {
          responseController.addError(error);
          responseController.close();
        }
        receivePort.close();
      }));
    }

    final RawResponseHeaders rawHeaders;
    try {
      rawHeaders = await responseHeadersCompleter.future;
    } catch (_) {
      _pendingRequests--;
      receivePort.close();
      unawaited(responseController.close());
      rethrow;
    }

    final statusCode = rawHeaders.statusCode;
    final isRedirect = !request.followRedirects &&
        statusCode >= 300 &&
        statusCode < 400;

    // Track when the response stream finishes so we can safely close
    // the session handle even if close() is called during a request.
    unawaited(responseController.done.then((_) {
      _pendingRequests--;
      _maybeCloseSession();
    }, onError: (_) {
      _pendingRequests--;
      _maybeCloseSession();
    }));

    return _StreamedResponseWithUrl(
      responseController.stream,
      rawHeaders.statusCode,
      url: rawHeaders.finalUrl,
      contentLength: rawHeaders.contentLength,
      reasonPhrase: rawHeaders.reasonPhrase,
      request: request,
      isRedirect: isRedirect,
      headers: rawHeaders.headers,
    );
  }

  bool _closePending = false;

  @override
  void close() {
    _closePending = true;
    _maybeCloseSession();
  }

  void _maybeCloseSession() {
    if (_closePending && _pendingRequests <= 0 && _hSession != null) {
      WinHttpCloseHandle(_hSession!);
      _hSession = null;
    }
  }
}
