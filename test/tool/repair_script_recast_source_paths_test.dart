import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rebinds a moved cache to indexed images when JSON and image leaves differ',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'script-recast-source-paths-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final cacheDir = Directory(_join(root.path, 'cache'))..createSync();
      final outputDir = Directory(_join(root.path, 'output'))..createSync();
      final sourceRoot = Directory(_join(root.path, 'source'))..createSync();
      final currentScript = Directory(
        _join(sourceRoot.path, 'premium', 'Moved Script'),
      )..createSync(recursive: true);
      final oldRoot = Directory(
        _join(root.path, 'old-library', 'Moved Script'),
      )..createSync(recursive: true);

      for (var index = 0; index < 3; index += 1) {
        File(_join(currentScript.path, 'Moved Script_p$index.png'))
            .writeAsBytesSync(const [0x89, 0x50, 0x4e, 0x47]);
        File(_join(oldRoot.path, 'nai_${index + 1}.json'))
            .writeAsStringSync('{"Description":"source ${index + 1}"}');
      }
      File(_join(currentScript.path, '.aitag-download-task.json'))
          .writeAsStringSync('{}');

      final cacheFile = File(_join(cacheDir.path, 'script-moved.json'));
      cacheFile.writeAsStringSync(
        jsonEncode({
          'scriptId': 'script-moved',
          'scriptName': 'Moved Script',
          'sourceRootPath': oldRoot.path,
          'sourceFingerprint': [
            'script-moved',
            _fingerprintPath(oldRoot.path),
            for (var index = 1; index <= 3; index += 1)
              '$index:nai_$index.json:${_fingerprintPath(_join(oldRoot.path, 'nai_$index.json'))}:hash$index',
          ].join('|'),
          'scriptSnapshot': {
            'id': 'script-moved',
            'name': 'Moved Script',
            'rootPath': oldRoot.path,
            'frames': [
              for (var index = 1; index <= 3; index += 1)
                {
                  'index': index,
                  'fileName': 'nai_$index.json',
                  'sourcePath': _join(oldRoot.path, 'nai_$index.json'),
                  'rawJson': '{"Description":"frame $index"}',
                  'parsed': {
                    'baseCaption': 'frame $index',
                    'charCaptions': ['girl'],
                  },
                },
            ],
          },
        }),
      );

      final result = await Process.run(
        'node',
        [
          'tool/repair_script_recast_source_paths.mjs',
          '--cache-dir',
          cacheDir.path,
          '--source-root',
          sourceRoot.path,
          '--output-dir',
          outputDir.path,
        ],
        workingDirectory: Directory.current.path,
      );

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      final report = jsonDecode(result.stdout as String) as Map;
      expect(report['updated_count'], 1);
      expect(report['unresolved_count'], 0);

      final repaired = jsonDecode(
        File(_join(outputDir.path, 'script-moved.json')).readAsStringSync(),
      ) as Map;
      expect(repaired['sourceRootPath'], currentScript.path);
      final snapshot = repaired['scriptSnapshot'] as Map;
      expect(snapshot['rootPath'], currentScript.path);
      final frames = (snapshot['frames'] as List).cast<Map>();
      for (var index = 0; index < frames.length; index += 1) {
        expect(
          frames[index]['sourcePath'],
          _join(currentScript.path, 'nai_${index + 1}.json'),
        );
        expect(
          frames[index]['sourceImagePath'],
          _join(currentScript.path, 'Moved Script_p$index.png'),
        );
        expect(frames[index]['rawJson'], contains('frame ${index + 1}'));
      }
      expect(
        repaired['sourceFingerprint'],
        contains(_fingerprintPath(currentScript.path)),
      );
    },
  );
}

String _join(String first, String second, [String? third]) {
  final joined = '$first${Platform.pathSeparator}$second';
  return third == null ? joined : '$joined${Platform.pathSeparator}$third';
}

String _fingerprintPath(String value) {
  final normalized = value.replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}
