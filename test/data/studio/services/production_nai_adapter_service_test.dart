import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/production_nai_adapter_service.dart';

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

  test('saveScriptRecastImage writes under script and version folders',
      () async {
    final saves = <String>[];
    final adapter = ProductionNaiAdapterService(
      endpoint: '',
      proxy: '',
      headers: const {},
      outputDirectory: r'C:\Users\tester\Documents\nai-generated',
      fetchData: (_) async => throw UnimplementedError(),
      processResponse: (bytes) => bytes,
      savePictureToFile: (bytes, fileName, saveDir) async {
        saves.add('$saveDir|$fileName|${bytes.length}');
      },
      resolvePictureSavePath: (fileName, saveDir) async =>
          '$saveDir\\$fileName',
    );
    final now = DateTime.utc(2026);
    final task = ProductionTask.scriptRecastFrame(
      id: 'task-1',
      planId: 'plan-1',
      title: 'Frame One',
      scriptId: 'script-1',
      scriptName: 'Rain Archive',
      recastRunId: 'run-1',
      frameIndex: 1,
      sourceFileName: '001.json',
      payload: const {'input': 'frame one'},
      createdAt: now,
      updatedAt: now,
    );
    final plan = ProductionPlan(
      id: 'plan-1',
      name: 'Hero Version A',
      tasks: [task],
      createdAt: now,
      updatedAt: now,
    );

    final path = await adapter.saveScriptRecastImage(
      Uint8List.fromList([1, 2, 3]),
      plan,
      task,
    );

    expect(
      saves.single,
      r'C:\Users\tester\Documents\nai-generated|Rain Archive\Hero Version A\001.png|3',
    );
    expect(
      path,
      r'C:\Users\tester\Documents\nai-generated\Rain Archive\Hero Version A\001.png',
    );
  });

  test('saveScriptRecastImage uses default output root for empty saveDir',
      () async {
    String? capturedFileName;
    String? capturedSaveDir;
    final adapter = ProductionNaiAdapterService(
      endpoint: '',
      proxy: '',
      headers: const {},
      outputDirectory: '',
      fetchData: (_) async => throw UnimplementedError(),
      processResponse: (bytes) => bytes,
      savePictureToFile: (bytes, fileName, saveDir) async {
        capturedFileName = fileName;
        capturedSaveDir = saveDir;
      },
      resolvePictureSavePath: (fileName, saveDir) async {
        if (saveDir.isEmpty) {
          return r'C:\Users\tester\Documents\nai-generated\' + fileName;
        }
        return '$saveDir\\$fileName';
      },
    );

    final task = _scriptTask();
    final path = await adapter.saveScriptRecastImage(
      Uint8List.fromList([1]),
      _scriptPlan(task),
      task,
    );

    expect(capturedSaveDir, '');
    expect(capturedFileName, r'Rain Archive\Hero Version A\001.png');
    expect(
      path,
      r'C:\Users\tester\Documents\nai-generated\Rain Archive\Hero Version A\001.png',
    );
  });

  test('saveScriptRecastImage checks collisions in default output root',
      () async {
    final defaultRoot =
        await Directory.systemTemp.createTemp('nai-default-root-');
    try {
      final existingDir = Directory(
        [
          defaultRoot.path,
          'Rain Archive',
          'Hero Version A',
        ].join(Platform.pathSeparator),
      );
      await existingDir.create(recursive: true);
      await File(
        [
          existingDir.path,
          '001.png',
        ].join(Platform.pathSeparator),
      ).writeAsBytes([0]);

      String? capturedFileName;
      String? capturedSaveDir;
      final adapter = ProductionNaiAdapterService(
        endpoint: '',
        proxy: '',
        headers: const {},
        outputDirectory: '',
        fetchData: (_) async => throw UnimplementedError(),
        processResponse: (bytes) => bytes,
        savePictureToFile: (bytes, fileName, saveDir) async {
          capturedFileName = fileName;
          capturedSaveDir = saveDir;
        },
        resolvePictureSavePath: (fileName, saveDir) async {
          if (saveDir.isEmpty) {
            return [
              defaultRoot.path,
              fileName,
            ].join(Platform.pathSeparator);
          }
          return [
            saveDir,
            fileName,
          ].join(Platform.pathSeparator);
        },
      );

      final task = _scriptTask();
      final path = await adapter.saveScriptRecastImage(
        Uint8List.fromList([1]),
        _scriptPlan(task),
        task,
      );

      expect(capturedSaveDir, '');
      expect(
        capturedFileName,
        endsWith(
          [
            'Rain Archive',
            'Hero Version A',
            '001-2.png',
          ].join(Platform.pathSeparator),
        ),
      );
      expect(
        path,
        [
          defaultRoot.path,
          'Rain Archive',
          'Hero Version A',
          '001-2.png',
        ].join(Platform.pathSeparator),
      );
    } finally {
      await defaultRoot.delete(recursive: true);
    }
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

    final task = _scriptTask();
    final plan = _scriptPlan(task);
    final path = await adapter.savePlanImage(
      Uint8List.fromList([1]),
      'nai.png',
      plan,
      task,
    );

    expect(saves, [r'C:\outputs|Rain Archive\Hero Version A\001.png|1']);
    expect(path, r'C:\outputs\Rain Archive\Hero Version A\001.png');
  });

  test('savePlanImage uses per-plan explicit output directory override',
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

    final task = _scriptTask();
    final plan = _scriptPlan(task).copyWith(
      executionSettings: const ProductionPlanExecutionSettings(
        outputDirectory: r'D:\batch-output',
      ),
    );
    final path = await adapter.savePlanImage(
      Uint8List.fromList([1]),
      'nai.png',
      plan,
      task,
    );

    expect(saves, [r'D:\batch-output|Rain Archive\Hero Version A\001.png|1']);
    expect(path, r'D:\batch-output\Rain Archive\Hero Version A\001.png');
  });

  test('savePlanImage preserves manual single-frame save behavior', () async {
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

    final task = _manualTask();
    final path = await adapter.savePlanImage(
      Uint8List.fromList([1]),
      'nai.png',
      _scriptPlan(task),
      task,
    );

    expect(saves, [r'C:\outputs|nai.png|1']);
    expect(path, r'C:\outputs\nai.png');
  });
}

final _createdAt = DateTime.utc(2026);

ProductionTask _scriptTask() {
  return ProductionTask.scriptRecastFrame(
    id: 'task-1',
    planId: 'plan-1',
    title: 'Frame One',
    scriptId: 'script-1',
    scriptName: 'Rain Archive',
    recastRunId: 'run-1',
    frameIndex: 1,
    sourceFileName: '001.json',
    payload: const {'input': 'frame one'},
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}

ProductionTask _manualTask() {
  return ProductionTask.manualSingleFrame(
    id: 'manual-1',
    planId: 'plan-1',
    title: 'Manual One',
    payload: const {'input': 'manual frame'},
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}

ProductionPlan _scriptPlan(ProductionTask task) {
  return ProductionPlan(
    id: 'plan-1',
    name: 'Hero Version A',
    tasks: [task],
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}
