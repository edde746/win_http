import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Converts a Dart [String] to a native UTF-16 string, executes [body],
/// and frees the native memory afterward.
T withWideString<T>(String s, T Function(Pointer<Utf16> ptr) body) {
  final ptr = s.toNativeUtf16(allocator: calloc);
  try {
    return body(ptr);
  } finally {
    calloc.free(ptr);
  }
}

/// Converts multiple strings to native UTF-16 pointers, executes [body],
/// and frees all native memory afterward.
///
/// Null entries in [strings] are converted to [nullptr].
T withWideStrings<T>(
  List<String?> strings,
  T Function(List<Pointer<Utf16>> ptrs) body,
) {
  final ptrs = <Pointer<Utf16>>[];
  try {
    for (final s in strings) {
      ptrs.add(s == null ? nullptr : s.toNativeUtf16(allocator: calloc));
    }
    return body(ptrs);
  } finally {
    for (final ptr in ptrs) {
      if (ptr != nullptr) {
        calloc.free(ptr);
      }
    }
  }
}
