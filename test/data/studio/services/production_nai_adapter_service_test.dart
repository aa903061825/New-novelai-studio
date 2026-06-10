import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/studio/services/production_nai_adapter_service.dart';

void main() {
  test('requestImage posts complete payload and processes response bytes',
      () async {
    ApiRequest? capturedRequest;
    final adapter = ProductionNaiAdapterService(
      endpoint: 'https://image.novelai.net/ai/generate-image',
      proxy: '127.0.0.1:7890',
      headers: const {'authorization': 'Bearer token'},
      outputDirectory: r'C:\outputs',
      fetchData: (request) async {
        capturedRequest = request;
        return ApiResponse(
          status: '200',
          data: Uint8List.fromList([1, 2, 3]),
        );
      },
      processResponse: (bytes) => Uint8List.fromList([...bytes, 4]),
      savePictureToFile: (bytes, fileName, saveDir) async {},
    );

    final bytes = await adapter.requestImage({
      'input': 'unchanged payload',
      'parameters': {'seed': 42},
    });

    expect(bytes, [1, 2, 3, 4]);
    expect(capturedRequest!.endpoint,
        'https://image.novelai.net/ai/generate-image');
    expect(capturedRequest!.proxy, '127.0.0.1:7890');
    expect(capturedRequest!.headers['authorization'], 'Bearer token');
    expect(capturedRequest!.payload['input'], 'unchanged payload');
    expect(capturedRequest!.payload['parameters']['seed'], 42);
  });

  test('requestImage throws on non-success status without processing response',
      () async {
    var processed = false;
    final adapter = ProductionNaiAdapterService(
      endpoint: 'https://example.invalid',
      proxy: '',
      headers: const {},
      outputDirectory: r'C:\outputs',
      fetchData: (request) async => ApiResponse(
        status: '500',
        data: Uint8List.fromList([101, 114, 114]),
      ),
      processResponse: (bytes) {
        processed = true;
        return bytes;
      },
      savePictureToFile: (bytes, fileName, saveDir) async {},
    );

    expect(
      () => adapter.requestImage({'input': 'bad'}),
      throwsA(isA<ProductionNaiApiException>()),
    );
    expect(processed, isFalse);
  });

  test('saveImage delegates to FileService contract and returns output path',
      () async {
    final saves = <String>[];
    final adapter = ProductionNaiAdapterService(
      endpoint: 'https://example.invalid',
      proxy: '',
      headers: const {},
      outputDirectory: r'C:\outputs',
      fetchData: (request) async =>
          ApiResponse(status: '200', data: Uint8List(0)),
      processResponse: (bytes) => bytes,
      savePictureToFile: (bytes, fileName, saveDir) async {
        saves.add('$saveDir|$fileName|${bytes.length}');
      },
      resolvePictureSavePath: (fileName, saveDir) async =>
          '$saveDir\\$fileName',
    );

    final path = await adapter.saveImage(Uint8List.fromList([9, 9]), 'nai.png');

    expect(saves, [r'C:\outputs|nai.png|2']);
    expect(path, r'C:\outputs\nai.png');
  });

  test('saveImage returns resolved default path when output directory is empty',
      () async {
    final saves = <String>[];
    final adapter = ProductionNaiAdapterService(
      endpoint: 'https://example.invalid',
      proxy: '',
      headers: const {},
      outputDirectory: '',
      fetchData: (request) async =>
          ApiResponse(status: '200', data: Uint8List(0)),
      processResponse: (bytes) => bytes,
      savePictureToFile: (bytes, fileName, saveDir) async {
        saves.add('$saveDir|$fileName|${bytes.length}');
      },
      resolvePictureSavePath: (fileName, saveDir) async =>
          r'C:\Users\tester\Documents\nai-generated\' + fileName,
    );

    final path = await adapter.saveImage(Uint8List.fromList([1]), 'p000.png');

    expect(saves, ['|p000.png|1']);
    expect(path, r'C:\Users\tester\Documents\nai-generated\p000.png');
  });

  test('savePlanImage isolates default output by production plan', () async {
    final saves = <String>[];
    final adapter = ProductionNaiAdapterService(
      endpoint: 'https://example.invalid',
      proxy: '',
      headers: const {},
      outputDirectory: '',
      fetchData: (request) async =>
          ApiResponse(status: '200', data: Uint8List(0)),
      processResponse: (bytes) => bytes,
      savePictureToFile: (bytes, fileName, saveDir) async {
        saves.add('$saveDir|$fileName|${bytes.length}');
      },
      resolvePictureSavePath: (fileName, saveDir) async =>
          r'C:\Users\tester\Documents\nai-generated\' + fileName,
    );

    final path = await adapter.savePlanImage(
      Uint8List.fromList([1]),
      'nai.png',
      'script-recast:plan/one',
      null,
    );

    expect(saves, ['|script-recast-plan-one/nai.png|1']);
    expect(
      path,
      r'C:\Users\tester\Documents\nai-generated\script-recast-plan-one/nai.png',
    );
  });

  test('savePlanImage preserves explicit output directory', () async {
    final saves = <String>[];
    final adapter = ProductionNaiAdapterService(
      endpoint: 'https://example.invalid',
      proxy: '',
      headers: const {},
      outputDirectory: r'C:\outputs',
      fetchData: (request) async =>
          ApiResponse(status: '200', data: Uint8List(0)),
      processResponse: (bytes) => bytes,
      savePictureToFile: (bytes, fileName, saveDir) async {
        saves.add('$saveDir|$fileName|${bytes.length}');
      },
      resolvePictureSavePath: (fileName, saveDir) async =>
          '$saveDir\\$fileName',
    );

    final path = await adapter.savePlanImage(
      Uint8List.fromList([1]),
      'nai.png',
      'script-recast-plan-one',
      null,
    );

    expect(saves, [r'C:\outputs|nai.png|1']);
    expect(path, r'C:\outputs\nai.png');
  });

  test('savePlanImage uses per-run explicit output directory override',
      () async {
    final saves = <String>[];
    final adapter = ProductionNaiAdapterService(
      endpoint: 'https://example.invalid',
      proxy: '',
      headers: const {},
      outputDirectory: '',
      fetchData: (request) async =>
          ApiResponse(status: '200', data: Uint8List(0)),
      processResponse: (bytes) => bytes,
      savePictureToFile: (bytes, fileName, saveDir) async {
        saves.add('$saveDir|$fileName|${bytes.length}');
      },
      resolvePictureSavePath: (fileName, saveDir) async =>
          '$saveDir\\$fileName',
    );

    final path = await adapter.savePlanImage(
      Uint8List.fromList([1]),
      'nai.png',
      'script-recast-plan-one',
      r'D:\batch-output',
    );

    expect(saves, [r'D:\batch-output|nai.png|1']);
    expect(path, r'D:\batch-output\nai.png');
  });
}
