import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/tools/nai_metadata_batch_processor.dart';
import 'package:nai_casrand/data/studio/tools/nai_metadata_parser.dart';

void main() {
  group('NaiMetadataBatchProcessor', () {
    test('processes entries in natural filename order and builds summaries',
        () {
      final result = NaiMetadataBatchProcessor.processEntries([
        NaiMetadataBatchInput(
          fileName: 'image10.txt',
          payload: {
            'Description': 'z scene',
            'Comment': jsonEncode({
              'width': 1024,
              'height': 768,
              'v4_prompt': {
                'caption': {
                  'base_caption': 'z scene',
                  'char_captions': [
                    {'char_caption': 'z char'},
                  ],
                },
              },
            }),
          },
        ),
        NaiMetadataBatchInput(
          fileName: 'image2.txt',
          payload: {
            'Comment': jsonEncode({
              'resolution': '832x1216',
              'v4_prompt': {
                'caption': {
                  'base_caption': 'a scene',
                  'char_captions': [
                    {
                      'char_caption': 'first char',
                      'coords': {'x': 0.25, 'y': 0.5},
                    },
                    {'caption': 'second char'},
                  ],
                },
              },
            }),
          },
        ),
      ]);

      expect(result.fileNames, ['image2.txt', 'image10.txt']);
      expect(result.allSummaryContent,
          'a scene, first char, second char\nz scene, z char');
      expect(result.sceneSummaryContent, 'a scene\nz scene');
      expect(result.charSummaryContents, {
        1: 'first char\nz char',
        2: 'second char\n,',
      });
      expect(result.resolutionsContent, '832x1216\n1024x768');
      expect(result.coordsContent, '0.25,0.5\n,');
      expect(result.outputFiles.keys, [
        '_ALL_SUMMARY.txt',
        '_SUMMARY_SCENE.txt',
        '_SUMMARY_CHAR_01.txt',
        '_SUMMARY_CHAR_02.txt',
        '_RESOLUTIONS.txt',
        '_COORDS.txt',
      ]);
      expect(result.failures, isEmpty);
    });

    test(
        'uses legacy placeholders for missing data and omits empty coords output',
        () {
      final result = NaiMetadataBatchProcessor.processEntries([
        const NaiMetadataBatchInput(fileName: 'solo.txt', payload: '{}'),
      ]);

      expect(result.allSummaryContent, ',');
      expect(result.sceneSummaryContent, ',');
      expect(result.charSummaryContents, isEmpty);
      expect(result.resolutionsContent, 'Unknown');
      expect(result.coordsContent, isNull);
      expect(result.outputFiles.containsKey('_COORDS.txt'), isFalse);
    });

    test('collects parser failures and emits ERR placeholders', () {
      final result = NaiMetadataBatchProcessor.processEntries(
        [
          const NaiMetadataBatchInput(fileName: 'bad.txt', payload: 'bad'),
        ],
        parser: (_) => throw const FormatException('broken metadata'),
      );

      expect(result.allSummaryContent, 'ERR');
      expect(result.sceneSummaryContent, ',');
      expect(result.resolutionsContent, 'ERR');
      expect(result.coordsContent, isNull);
      expect(result.failures, hasLength(1));
      expect(result.failures.single.fileName, 'bad.txt');
      expect(result.failures.single.error, contains('broken metadata'));
    });

    test('reads metadata files from a directory and writes legacy output files',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('nai_batch_test_');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      await File('${directory.path}${Platform.pathSeparator}file2.json')
          .writeAsString(jsonEncode({
        'Description': 'second scene',
        'width': 640,
        'height': 960,
      }));
      await File('${directory.path}${Platform.pathSeparator}file10.json')
          .writeAsString(jsonEncode({
        'Description': 'tenth scene',
        'width': 960,
        'height': 640,
      }));

      final result =
          await NaiMetadataBatchProcessor.processDirectory(directory);

      expect(result.fileNames, ['file2.json', 'file10.json']);
      expect(
        await File('${directory.path}${Platform.pathSeparator}_ALL_SUMMARY.txt')
            .readAsString(),
        'second scene\ntenth scene',
      );
      expect(
        await File('${directory.path}${Platform.pathSeparator}_RESOLUTIONS.txt')
            .readAsString(),
        '640x960\n960x640',
      );
      expect(
        await File('${directory.path}${Platform.pathSeparator}_COORDS.txt')
            .exists(),
        isFalse,
      );
      expect(result.failures, isEmpty);
    });

    test('supports custom parsed results without coords output', () {
      final parsed = NaiMetadataParseResult(
        prompt: 'scene',
        rawContent: 'scene',
        parameters: const {},
        width: null,
        height: null,
        charCaptions: const ['char'],
        coords: const [],
        hasStructuredMetadata: true,
      );

      final result = NaiMetadataBatchProcessor.processEntries(
        [const NaiMetadataBatchInput(fileName: 'a.txt', payload: '')],
        parser: (_) => parsed,
      );

      expect(result.allSummaryContent, 'scene, char');
      expect(result.coordsContent, isNull);
    });
  });
}
