import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:http/io_client.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:http/http.dart' as http;

class ApiService {
  Future<ApiResponse> fetchData(ApiRequest request) async {
    final url = Uri.parse(request.endpoint);
    final client = createHttpClient(request.proxy);
    final stopwatch = Stopwatch()..start();
    _logRequestStart(request, method: 'POST');
    try {
      final responseFuture = client == null
          ? http.post(
              url,
              headers: request.headers,
              body: json.encode(request.payload),
            )
          : client.post(
              url,
              headers: request.headers,
              body: json.encode(request.payload),
            );
      final response = await _withTimeout(responseFuture, request);
      _logRequestEnd(request, response.statusCode, stopwatch.elapsed);
      return ApiResponse(
        status: response.statusCode.toString(),
        data: response.bodyBytes,
      );
    } catch (error) {
      _logRequestError(request, error, stopwatch.elapsed);
      rethrow;
    } finally {
      client?.close();
    }
  }

  Future<ApiResponse> fetchGetData(ApiRequest request) async {
    final url = Uri.parse(request.endpoint);
    final client = createHttpClient(request.proxy);
    final stopwatch = Stopwatch()..start();
    _logRequestStart(request, method: 'GET');
    try {
      final responseFuture = client == null
          ? http.get(url, headers: request.headers)
          : client.get(url, headers: request.headers);
      final response = await _withTimeout(responseFuture, request);
      _logRequestEnd(request, response.statusCode, stopwatch.elapsed);
      return ApiResponse(
        status: response.statusCode.toString(),
        data: response.bodyBytes,
      );
    } catch (error) {
      _logRequestError(request, error, stopwatch.elapsed);
      rethrow;
    } finally {
      client?.close();
    }
  }

  Future<ApiResponse> streamData(
    ApiRequest request, {
    required void Function(String text) onTextChunk,
  }) async {
    final url = Uri.parse(request.endpoint);
    final client = createHttpClient(request.proxy) ?? http.Client();
    final stopwatch = Stopwatch()..start();
    _logRequestStart(request, method: 'POST');
    try {
      final httpRequest = http.Request('POST', url)
        ..headers.addAll(request.headers)
        ..body = json.encode(request.payload);
      final response = await _withTimeout(client.send(httpRequest), request);
      final body = StringBuffer();
      final streamFuture =
          response.stream.transform(utf8.decoder).listen((chunk) {
        body.write(chunk);
        onTextChunk(chunk);
      }).asFuture<void>();
      await _withTimeout(streamFuture, request);
      _logRequestEnd(request, response.statusCode, stopwatch.elapsed);
      return ApiResponse(
        status: response.statusCode.toString(),
        data: Uint8List.fromList(utf8.encode(body.toString())),
      );
    } catch (error) {
      _logRequestError(request, error, stopwatch.elapsed);
      rethrow;
    } finally {
      client.close();
    }
  }

  http.Client? createHttpClient(String proxy) {
    if (proxy == '') return null;
    final ioClient = HttpClient();
    ioClient.findProxy = (uri) => 'PROXY $proxy';
    ioClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return IOClient(ioClient);
  }

  Future<T> _withTimeout<T>(
    Future<T> responseFuture,
    ApiRequest request,
  ) {
    final timeout = request.timeout;
    if (timeout == null) {
      return responseFuture;
    }
    return responseFuture.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        _timeoutMessage(request, timeout),
        timeout,
      ),
    );
  }

  String _timeoutMessage(ApiRequest request, Duration timeout) {
    final label = request.logLabel.trim();
    final name = label.isEmpty ? 'API request' : label;
    return '$name timed out after ${timeout.inSeconds}s: ${request.endpoint}';
  }

  void _logRequestStart(
    ApiRequest request, {
    required String method,
  }) {
    final label = request.logLabel.trim();
    if (label.isEmpty) {
      return;
    }
    developer.log(
      '$method ${request.endpoint} timeout=${request.timeout ?? 'none'}',
      name: 'ApiService.$label',
    );
  }

  void _logRequestEnd(
    ApiRequest request,
    int statusCode,
    Duration elapsed,
  ) {
    final label = request.logLabel.trim();
    if (label.isEmpty) {
      return;
    }
    developer.log(
      'HTTP $statusCode in ${elapsed.inMilliseconds}ms',
      name: 'ApiService.$label',
    );
  }

  void _logRequestError(
    ApiRequest request,
    Object error,
    Duration elapsed,
  ) {
    final label = request.logLabel.trim();
    if (label.isEmpty) {
      return;
    }
    developer.log(
      'failed after ${elapsed.inMilliseconds}ms: $error',
      name: 'ApiService.$label',
      error: error,
    );
  }
}
