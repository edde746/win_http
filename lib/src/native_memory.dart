import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi/winhttp_bindings.dart';
import 'ffi/winhttp_constants.dart';
import 'win_http_exception.dart';

/// Queries a string header value from an HTTP response.
///
/// Uses the two-call pattern: first call with zero-length buffer to get the
/// required size, then allocate and call again.
///
/// Returns null if the header is not found.
String? queryHeaderString(int hRequest, int dwInfoLevel) {
  final pSize = calloc<Uint32>();
  try {
    pSize.value = 0;

    // First call: get required buffer size.
    // Expected to return FALSE. We check pSize to determine outcome:
    // - pSize > 0: buffer too small (normal flow, proceed to second call)
    // - pSize == 0: header not found or other error
    SetLastError(0);
    final firstResult = WinHttpQueryHeaders(
      hRequest,
      dwInfoLevel,
      nullptr,
      nullptr,
      pSize,
      nullptr,
    );

    if (firstResult != 0) {
      // Shouldn't happen with null buffer, but handle it.
      return '';
    }

    // Check if the buffer size was set — indicates insufficient buffer.
    if (pSize.value == 0) {
      // Header not found or other error.
      return null;
    }

    // Second call: read into correctly sized buffer.
    final bufferSize = pSize.value;
    final pBuffer = calloc<Uint8>(bufferSize);
    try {
      SetLastError(0);
      final secondResult = WinHttpQueryHeaders(
        hRequest,
        dwInfoLevel,
        nullptr,
        pBuffer.cast(),
        pSize,
        nullptr,
      );

      if (secondResult == 0) {
        // Second call failed unexpectedly.
        final error = GetLastError();
        throw WinHttpException(
            error != 0 ? error : ERROR_WINHTTP_HEADER_NOT_FOUND,
            'WinHttpQueryHeaders');
      }

      return pBuffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(pBuffer);
    }
  } finally {
    calloc.free(pSize);
  }
}

/// Queries a numeric (DWORD) header value from an HTTP response.
int queryHeaderInt(int hRequest, int dwInfoLevel) {
  final pValue = calloc<Uint32>();
  final pSize = calloc<Uint32>();
  pSize.value = sizeOf<Uint32>();
  try {
    callWinHttp(
      'WinHttpQueryHeaders',
      () => WinHttpQueryHeaders(
          hRequest, dwInfoLevel, nullptr, pValue.cast(), pSize, nullptr),
    );
    return pValue.value;
  } finally {
    calloc.free(pValue);
    calloc.free(pSize);
  }
}

/// Queries a string option from an HINTERNET handle.
///
/// Uses the two-call pattern for buffer sizing.
/// Returns null if the option is not available.
String? queryOptionString(int hInternet, int dwOption) {
  final pSize = calloc<Uint32>();
  try {
    pSize.value = 0;

    // First call: get required buffer size.
    WinHttpQueryOption(hInternet, dwOption, nullptr, pSize);

    if (pSize.value == 0) {
      return null;
    }

    // Second call: read into correctly sized buffer.
    final bufferSize = pSize.value;
    final pBuffer = calloc<Uint8>(bufferSize);
    try {
      SetLastError(0);
      final result =
          WinHttpQueryOption(hInternet, dwOption, pBuffer.cast(), pSize);

      if (result == 0) {
        return null;
      }

      return pBuffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(pBuffer);
    }
  } finally {
    calloc.free(pSize);
  }
}

/// Sets a DWORD option on a WinHTTP handle.
void setDwordOption(int hInternet, int option, int value) {
  final pValue = calloc<Uint32>();
  try {
    pValue.value = value;
    callWinHttp(
      'WinHttpSetOption',
      () =>
          WinHttpSetOption(hInternet, option, pValue.cast(), sizeOf<Uint32>()),
    );
  } finally {
    calloc.free(pValue);
  }
}
