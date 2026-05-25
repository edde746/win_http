import 'package:test/test.dart';
import 'package:win_http/src/request_error_message.dart';

void main() {
  group('requestErrorMessage', () {
    test('reports DNS failure while resolving host', () {
      expect(
        requestErrorMessage(
          phase: RequestPhase.sendingRequest,
          progress: RequestProgress.resolvingName,
          secureFailure: false,
        ),
        'Could not resolve host',
      );
    });

    test('reports connect failure after name resolution', () {
      expect(
        requestErrorMessage(
          phase: RequestPhase.sendingRequest,
          progress: RequestProgress.connectingToServer,
          secureFailure: false,
        ),
        'Could not connect to the server',
      );
    });

    test('reports TLS failure when secure failure status was observed', () {
      expect(
        requestErrorMessage(
          phase: RequestPhase.sendingRequest,
          progress: RequestProgress.receivingResponse,
          secureFailure: true,
        ),
        'TLS certificate validation failed',
      );
    });

    test('falls back to phase when no durable status was observed', () {
      expect(
        requestErrorMessage(
          phase: RequestPhase.sendingRequest,
          progress: RequestProgress.initial,
          secureFailure: false,
        ),
        'Failed to send request',
      );
    });
  });
}
