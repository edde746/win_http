/// WinHTTP constants for use with the raw FFI bindings.
library;

// Access type constants for WinHttpOpen.
// ignore: constant_identifier_names
const int WINHTTP_ACCESS_TYPE_NO_PROXY = 1;
// ignore: constant_identifier_names
const int WINHTTP_ACCESS_TYPE_NAMED_PROXY = 3;
// ignore: constant_identifier_names
const int WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY = 4; // Recommended on 8.1+

// Flag constants for WinHttpOpenRequest.
// ignore: constant_identifier_names
const int WINHTTP_FLAG_SECURE = 0x00800000;

// Header modification flags for WinHttpAddRequestHeaders.
// ignore: constant_identifier_names
const int WINHTTP_ADDREQ_FLAG_ADD = 0x20000000;
// ignore: constant_identifier_names
const int WINHTTP_ADDREQ_FLAG_REPLACE = 0x80000000;

// Query header info level constants for WinHttpQueryHeaders.
// ignore: constant_identifier_names
const int WINHTTP_QUERY_STATUS_CODE = 19;
// ignore: constant_identifier_names
const int WINHTTP_QUERY_STATUS_TEXT = 20;
// ignore: constant_identifier_names
const int WINHTTP_QUERY_RAW_HEADERS_CRLF = 22;
// ignore: constant_identifier_names
const int WINHTTP_QUERY_FLAG_NUMBER = 0x20000000;

// Option constants for WinHttpSetOption / WinHttpQueryOption.
// ignore: constant_identifier_names
const int WINHTTP_OPTION_URL = 34;
// ignore: constant_identifier_names
const int WINHTTP_OPTION_DISABLE_FEATURE = 63;
// ignore: constant_identifier_names
const int WINHTTP_OPTION_REDIRECT_POLICY = 68;
// ignore: constant_identifier_names
const int WINHTTP_OPTION_MAX_HTTP_AUTOMATIC_REDIRECTS = 89;
// ignore: constant_identifier_names
const int WINHTTP_OPTION_DECOMPRESSION = 118;

// Redirect policy values.
// ignore: constant_identifier_names
const int WINHTTP_OPTION_REDIRECT_POLICY_NEVER = 0;
// ignore: constant_identifier_names
const int WINHTTP_OPTION_REDIRECT_POLICY_DISALLOW_HTTPS_TO_HTTP = 1;
// ignore: constant_identifier_names
const int WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS = 2;

// Decompression flags (Windows 8.1+).
// ignore: constant_identifier_names
const int WINHTTP_DECOMPRESSION_FLAG_GZIP = 0x00000001;
// ignore: constant_identifier_names
const int WINHTTP_DECOMPRESSION_FLAG_DEFLATE = 0x00000002;
// ignore: constant_identifier_names
const int WINHTTP_DECOMPRESSION_FLAG_ALL =
    WINHTTP_DECOMPRESSION_FLAG_GZIP | WINHTTP_DECOMPRESSION_FLAG_DEFLATE;

// Disable feature flags for WINHTTP_OPTION_DISABLE_FEATURE.
// ignore: constant_identifier_names
const int WINHTTP_DISABLE_COOKIES = 0x00000001;
// ignore: constant_identifier_names
const int WINHTTP_DISABLE_REDIRECTS = 0x00000002;
// Default ports.
// ignore: constant_identifier_names
const int INTERNET_DEFAULT_HTTP_PORT = 80;
// ignore: constant_identifier_names
const int INTERNET_DEFAULT_HTTPS_PORT = 443;
// Win32 error codes.
// ignore: constant_identifier_names
const int ERROR_SUCCESS = 0;
// ignore: constant_identifier_names
const int ERROR_INSUFFICIENT_BUFFER = 122;

// WinHTTP error codes.
// ignore: constant_identifier_names
const int ERROR_WINHTTP_TIMEOUT = 12002;
// ignore: constant_identifier_names
const int ERROR_WINHTTP_NAME_NOT_RESOLVED = 12007;
// ignore: constant_identifier_names
const int ERROR_WINHTTP_CANNOT_CONNECT = 12029;
// ignore: constant_identifier_names
const int ERROR_WINHTTP_CONNECTION_ERROR = 12030;
// ignore: constant_identifier_names
const int ERROR_WINHTTP_RESEND_REQUEST = 12032;
// ignore: constant_identifier_names
const int ERROR_WINHTTP_HEADER_NOT_FOUND = 12150;
// ignore: constant_identifier_names
const int ERROR_WINHTTP_REDIRECT_FAILED = 12156;
// ignore: constant_identifier_names
const int ERROR_WINHTTP_SECURE_FAILURE = 12175;
