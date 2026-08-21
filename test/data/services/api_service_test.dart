import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/services/api_service.dart';

void main() {
  test('fetchData applies request timeout', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) {
      // Keep the response pending so the client-side timeout is exercised.
    });

    try {
      final service = ApiService();
      final future = service.fetchData(
        ApiRequest(
          endpoint: 'http://127.0.0.1:${server.port}/hang',
          proxy: '',
          headers: const {'Content-Type': 'application/json'},
          payload: const {'ping': true},
          timeout: const Duration(milliseconds: 20),
          logLabel: 'api-service-test',
        ),
      );

      await expectLater(
        future,
        throwsA(isA<TimeoutException>()),
      );
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('fetchData returns response before timeout', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true}))
        ..close();
    });

    try {
      final service = ApiService();
      final response = await service.fetchData(
        ApiRequest(
          endpoint: 'http://127.0.0.1:${server.port}/ok',
          proxy: '',
          headers: const {'Content-Type': 'application/json'},
          payload: const {'ping': true},
          timeout: const Duration(seconds: 1),
        ),
      );

      expect(response.status, '200');
      expect(utf8.decode(response.data), '{"ok":true}');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('fetchGetData performs a GET request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? method;
    final subscription = server.listen((request) {
      method = request.method;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'usage': true}))
        ..close();
    });

    try {
      final response = await ApiService().fetchGetData(
        ApiRequest(
          endpoint: 'http://127.0.0.1:${server.port}/user/data',
          proxy: '',
          headers: const {'Authorization': 'Bearer simulated'},
          payload: const {},
          timeout: const Duration(seconds: 1),
        ),
      );

      expect(method, 'GET');
      expect(response.status, '200');
      expect(utf8.decode(response.data), '{"usage":true}');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
