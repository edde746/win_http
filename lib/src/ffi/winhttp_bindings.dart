/// Hand-written FFI bindings to winhttp.dll and kernel32.dll.
///
/// Only the functions needed by this package are bound.
/// All functions use `isLeaf: true` to prevent the Dart runtime from
/// making system calls between our FFI call and GetLastError().
library;

// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

final _winhttp = DynamicLibrary.open('winhttp.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

// ---------------------------------------------------------------------------
// Session / Connection / Request Handle Management
// ---------------------------------------------------------------------------

/// Opens an HTTP session.
///
/// Returns an HINTERNET session handle, or 0 on failure.
int WinHttpOpen(
  Pointer<Utf16> pszAgentW,
  int dwAccessType,
  Pointer<Utf16> pszProxyW,
  Pointer<Utf16> pszProxyBypassW,
  int dwFlags,
) =>
    _WinHttpOpen(
        pszAgentW, dwAccessType, pszProxyW, pszProxyBypassW, dwFlags);

final _WinHttpOpen = _winhttp.lookupFunction<
    IntPtr Function(
      Pointer<Utf16> pszAgentW,
      Uint32 dwAccessType,
      Pointer<Utf16> pszProxyW,
      Pointer<Utf16> pszProxyBypassW,
      Uint32 dwFlags,
    ),
    int Function(
      Pointer<Utf16> pszAgentW,
      int dwAccessType,
      Pointer<Utf16> pszProxyW,
      Pointer<Utf16> pszProxyBypassW,
      int dwFlags,
    )>('WinHttpOpen', isLeaf: true);

/// Specifies the target server of an HTTP request.
///
/// Returns an HINTERNET connection handle, or 0 on failure.
int WinHttpConnect(
  int hSession,
  Pointer<Utf16> pswzServerName,
  int nServerPort,
  int dwReserved,
) =>
    _WinHttpConnect(hSession, pswzServerName, nServerPort, dwReserved);

final _WinHttpConnect = _winhttp.lookupFunction<
    IntPtr Function(
      IntPtr hSession,
      Pointer<Utf16> pswzServerName,
      Uint16 nServerPort,
      Uint32 dwReserved,
    ),
    int Function(
      int hSession,
      Pointer<Utf16> pswzServerName,
      int nServerPort,
      int dwReserved,
    )>('WinHttpConnect', isLeaf: true);

/// Creates an HTTP request handle.
///
/// Returns an HINTERNET request handle, or 0 on failure.
int WinHttpOpenRequest(
  int hConnect,
  Pointer<Utf16> pwszVerb,
  Pointer<Utf16> pwszObjectName,
  Pointer<Utf16> pwszVersion,
  Pointer<Utf16> pwszReferrer,
  Pointer<Pointer<Utf16>> ppwszAcceptTypes,
  int dwFlags,
) =>
    _WinHttpOpenRequest(hConnect, pwszVerb, pwszObjectName, pwszVersion,
        pwszReferrer, ppwszAcceptTypes, dwFlags);

final _WinHttpOpenRequest = _winhttp.lookupFunction<
    IntPtr Function(
      IntPtr hConnect,
      Pointer<Utf16> pwszVerb,
      Pointer<Utf16> pwszObjectName,
      Pointer<Utf16> pwszVersion,
      Pointer<Utf16> pwszReferrer,
      Pointer<Pointer<Utf16>> ppwszAcceptTypes,
      Uint32 dwFlags,
    ),
    int Function(
      int hConnect,
      Pointer<Utf16> pwszVerb,
      Pointer<Utf16> pwszObjectName,
      Pointer<Utf16> pwszVersion,
      Pointer<Utf16> pwszReferrer,
      Pointer<Pointer<Utf16>> ppwszAcceptTypes,
      int dwFlags,
    )>('WinHttpOpenRequest', isLeaf: true);

/// Closes a single HINTERNET handle.
///
/// Returns non-zero on success, 0 on failure.
int WinHttpCloseHandle(int hInternet) => _WinHttpCloseHandle(hInternet);

final _WinHttpCloseHandle = _winhttp.lookupFunction<
    Int32 Function(IntPtr hInternet),
    int Function(int hInternet)>('WinHttpCloseHandle', isLeaf: true);

// ---------------------------------------------------------------------------
// Request Configuration
// ---------------------------------------------------------------------------

/// Adds one or more HTTP request headers to the request handle.
///
/// Returns non-zero on success, 0 on failure.
int WinHttpAddRequestHeaders(
  int hRequest,
  Pointer<Utf16> lpszHeaders,
  int dwHeadersLength,
  int dwModifiers,
) =>
    _WinHttpAddRequestHeaders(
        hRequest, lpszHeaders, dwHeadersLength, dwModifiers);

final _WinHttpAddRequestHeaders = _winhttp.lookupFunction<
    Int32 Function(
      IntPtr hRequest,
      Pointer<Utf16> lpszHeaders,
      Uint32 dwHeadersLength,
      Uint32 dwModifiers,
    ),
    int Function(
      int hRequest,
      Pointer<Utf16> lpszHeaders,
      int dwHeadersLength,
      int dwModifiers,
    )>('WinHttpAddRequestHeaders', isLeaf: true);

/// Sets an option on an HINTERNET handle.
///
/// Returns non-zero on success, 0 on failure.
int WinHttpSetOption(
  int hInternet,
  int dwOption,
  Pointer<Void> lpBuffer,
  int dwBufferLength,
) =>
    _WinHttpSetOption(hInternet, dwOption, lpBuffer, dwBufferLength);

final _WinHttpSetOption = _winhttp.lookupFunction<
    Int32 Function(
      IntPtr hInternet,
      Uint32 dwOption,
      Pointer<Void> lpBuffer,
      Uint32 dwBufferLength,
    ),
    int Function(
      int hInternet,
      int dwOption,
      Pointer<Void> lpBuffer,
      int dwBufferLength,
    )>('WinHttpSetOption', isLeaf: true);

/// Queries an option on an HINTERNET handle.
///
/// Returns non-zero on success, 0 on failure.
int WinHttpQueryOption(
  int hInternet,
  int dwOption,
  Pointer<Void> lpBuffer,
  Pointer<Uint32> lpdwBufferLength,
) =>
    _WinHttpQueryOption(hInternet, dwOption, lpBuffer, lpdwBufferLength);

final _WinHttpQueryOption = _winhttp.lookupFunction<
    Int32 Function(
      IntPtr hInternet,
      Uint32 dwOption,
      Pointer<Void> lpBuffer,
      Pointer<Uint32> lpdwBufferLength,
    ),
    int Function(
      int hInternet,
      int dwOption,
      Pointer<Void> lpBuffer,
      Pointer<Uint32> lpdwBufferLength,
    )>('WinHttpQueryOption', isLeaf: true);

/// Sets timeout values for the resolve, connect, send, and receive operations.
///
/// Returns non-zero on success, 0 on failure.
int WinHttpSetTimeouts(
  int hInternet,
  int nResolveTimeout,
  int nConnectTimeout,
  int nSendTimeout,
  int nReceiveTimeout,
) =>
    _WinHttpSetTimeouts(hInternet, nResolveTimeout, nConnectTimeout,
        nSendTimeout, nReceiveTimeout);

final _WinHttpSetTimeouts = _winhttp.lookupFunction<
    Int32 Function(
      IntPtr hInternet,
      Int32 nResolveTimeout,
      Int32 nConnectTimeout,
      Int32 nSendTimeout,
      Int32 nReceiveTimeout,
    ),
    int Function(
      int hInternet,
      int nResolveTimeout,
      int nConnectTimeout,
      int nSendTimeout,
      int nReceiveTimeout,
    )>('WinHttpSetTimeouts', isLeaf: true);

// ---------------------------------------------------------------------------
// Sending Request & Body
// ---------------------------------------------------------------------------

/// Sends the specified request to the HTTP server.
///
/// Returns non-zero on success, 0 on failure.
///
/// Note: NOT marked `isLeaf` because WinHttpSendRequest in synchronous mode
/// blocks and may process Windows messages internally.
int WinHttpSendRequest(
  int hRequest,
  Pointer<Utf16> lpszHeaders,
  int dwHeadersLength,
  Pointer<Void> lpOptional,
  int dwOptionalLength,
  int dwTotalLength,
  int dwContext,
) =>
    _WinHttpSendRequest(hRequest, lpszHeaders, dwHeadersLength, lpOptional,
        dwOptionalLength, dwTotalLength, dwContext);

final _WinHttpSendRequest = _winhttp.lookupFunction<
    Int32 Function(
      IntPtr hRequest,
      Pointer<Utf16> lpszHeaders,
      Uint32 dwHeadersLength,
      Pointer<Void> lpOptional,
      Uint32 dwOptionalLength,
      Uint32 dwTotalLength,
      IntPtr dwContext,
    ),
    int Function(
      int hRequest,
      Pointer<Utf16> lpszHeaders,
      int dwHeadersLength,
      Pointer<Void> lpOptional,
      int dwOptionalLength,
      int dwTotalLength,
      int dwContext,
    )>('WinHttpSendRequest');

/// Writes request body data to an HTTP server.
///
/// Returns non-zero on success, 0 on failure.
int WinHttpWriteData(
  int hRequest,
  Pointer<Void> lpBuffer,
  int dwNumberOfBytesToWrite,
  Pointer<Uint32> lpdwNumberOfBytesWritten,
) =>
    _WinHttpWriteData(
        hRequest, lpBuffer, dwNumberOfBytesToWrite, lpdwNumberOfBytesWritten);

final _WinHttpWriteData = _winhttp.lookupFunction<
    Int32 Function(
      IntPtr hRequest,
      Pointer<Void> lpBuffer,
      Uint32 dwNumberOfBytesToWrite,
      Pointer<Uint32> lpdwNumberOfBytesWritten,
    ),
    int Function(
      int hRequest,
      Pointer<Void> lpBuffer,
      int dwNumberOfBytesToWrite,
      Pointer<Uint32> lpdwNumberOfBytesWritten,
    )>('WinHttpWriteData');

// ---------------------------------------------------------------------------
// Receiving Response
// ---------------------------------------------------------------------------

/// Waits to receive the response headers from the server.
///
/// Returns non-zero on success, 0 on failure.
///
/// Note: NOT marked `isLeaf` because it blocks until the response arrives.
int WinHttpReceiveResponse(int hRequest, Pointer<Void> lpReserved) =>
    _WinHttpReceiveResponse(hRequest, lpReserved);

final _WinHttpReceiveResponse = _winhttp.lookupFunction<
    Int32 Function(IntPtr hRequest, Pointer<Void> lpReserved),
    int Function(
        int hRequest, Pointer<Void> lpReserved)>('WinHttpReceiveResponse');

/// Retrieves header information associated with an HTTP request.
///
/// Returns non-zero on success, 0 on failure.
int WinHttpQueryHeaders(
  int hRequest,
  int dwInfoLevel,
  Pointer<Utf16> pwszName,
  Pointer<Void> lpBuffer,
  Pointer<Uint32> lpdwBufferLength,
  Pointer<Uint32> lpdwIndex,
) =>
    _WinHttpQueryHeaders(hRequest, dwInfoLevel, pwszName, lpBuffer,
        lpdwBufferLength, lpdwIndex);

final _WinHttpQueryHeaders = _winhttp.lookupFunction<
    Int32 Function(
      IntPtr hRequest,
      Uint32 dwInfoLevel,
      Pointer<Utf16> pwszName,
      Pointer<Void> lpBuffer,
      Pointer<Uint32> lpdwBufferLength,
      Pointer<Uint32> lpdwIndex,
    ),
    int Function(
      int hRequest,
      int dwInfoLevel,
      Pointer<Utf16> pwszName,
      Pointer<Void> lpBuffer,
      Pointer<Uint32> lpdwBufferLength,
      Pointer<Uint32> lpdwIndex,
    )>('WinHttpQueryHeaders', isLeaf: true);

/// Returns the amount of data, in bytes, available to be read.
///
/// Returns non-zero on success, 0 on failure.
///
/// Note: NOT marked `isLeaf` because it may block waiting for data.
int WinHttpQueryDataAvailable(
  int hRequest,
  Pointer<Uint32> lpdwNumberOfBytesAvailable,
) =>
    _WinHttpQueryDataAvailable(hRequest, lpdwNumberOfBytesAvailable);

final _WinHttpQueryDataAvailable = _winhttp.lookupFunction<
    Int32 Function(
        IntPtr hRequest, Pointer<Uint32> lpdwNumberOfBytesAvailable),
    int Function(int hRequest,
        Pointer<Uint32> lpdwNumberOfBytesAvailable)>('WinHttpQueryDataAvailable');

/// Reads data from a handle opened by WinHttpOpenRequest.
///
/// Returns non-zero on success, 0 on failure.
///
/// Note: NOT marked `isLeaf` because it may block waiting for data.
int WinHttpReadData(
  int hRequest,
  Pointer<Void> lpBuffer,
  int dwNumberOfBytesToRead,
  Pointer<Uint32> lpdwNumberOfBytesRead,
) =>
    _WinHttpReadData(
        hRequest, lpBuffer, dwNumberOfBytesToRead, lpdwNumberOfBytesRead);

final _WinHttpReadData = _winhttp.lookupFunction<
    Int32 Function(
      IntPtr hRequest,
      Pointer<Void> lpBuffer,
      Uint32 dwNumberOfBytesToRead,
      Pointer<Uint32> lpdwNumberOfBytesRead,
    ),
    int Function(
      int hRequest,
      Pointer<Void> lpBuffer,
      int dwNumberOfBytesToRead,
      Pointer<Uint32> lpdwNumberOfBytesRead,
    )>('WinHttpReadData');

// ---------------------------------------------------------------------------
// Error Handling (kernel32.dll)
// ---------------------------------------------------------------------------

/// Retrieves the calling thread's last-error code value.
int GetLastError() => _GetLastError();

final _GetLastError = _kernel32.lookupFunction<Uint32 Function(),
    int Function()>('GetLastError', isLeaf: true);

/// Sets the last-error code for the calling thread.
void SetLastError(int dwErrCode) => _SetLastError(dwErrCode);

final _SetLastError = _kernel32.lookupFunction<Void Function(Uint32 dwErrCode),
    void Function(int dwErrCode)>('SetLastError', isLeaf: true);
