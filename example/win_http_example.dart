import 'dart:io';

import 'package:win_http/win_http.dart';

void main() async {
  if (!Platform.isWindows) {
    print('This example only works on Windows.');
    return;
  }

  final client = WinHttpClient.defaultConfiguration();
  try {
    final response = await client.get(
      Uri.https('www.googleapis.com', '/books/v1/volumes', {'q': 'dart'}),
    );
    print('Status: ${response.statusCode}');
    print('Body (first 200 chars): ${response.body.substring(0, 200)}...');
  } finally {
    client.close();
  }
}
