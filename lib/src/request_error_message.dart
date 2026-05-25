// Request lifecycle state that can be tracked without retaining borrowed
// WinHTTP callback pointers across NativeCallable.listener dispatch.
enum RequestPhase {
  sendingRequest,
  receivingResponse,
  readingData,
  done,
  error,
}

enum RequestProgress {
  initial,
  resolvingName,
  nameResolved,
  connectingToServer,
  connectedToServer,
  sendingRequest,
  requestSent,
  receivingResponse,
  responseReceived,
  readingData,
}

String requestErrorMessage({
  required RequestPhase phase,
  required RequestProgress progress,
  required bool secureFailure,
}) {
  if (secureFailure) return 'TLS certificate validation failed';

  return switch (progress) {
    RequestProgress.resolvingName => 'Could not resolve host',
    RequestProgress.nameResolved ||
    RequestProgress.connectingToServer =>
      'Could not connect to the server',
    RequestProgress.connectedToServer ||
    RequestProgress.sendingRequest ||
    RequestProgress.requestSent =>
      'The connection was reset or terminated',
    RequestProgress.receivingResponse ||
    RequestProgress.responseReceived =>
      'Failed to receive response',
    RequestProgress.readingData => 'Connection closed while receiving data',
    RequestProgress.initial => switch (phase) {
        RequestPhase.sendingRequest => 'Failed to send request',
        RequestPhase.receivingResponse => 'Failed to receive response',
        RequestPhase.readingData => 'Connection closed while receiving data',
        _ => 'WinHTTP request failed',
      },
  };
}
