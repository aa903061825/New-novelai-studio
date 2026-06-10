import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_recast_parser_service.dart';
import 'package:nai_casrand/data/studio/services/workbench_metadata_import_service.dart';
import 'package:nai_casrand/data/studio/tools/nai_metadata_parser.dart';

void main() {
  group('ScriptRecastParserService', () {
    test('scans nai json frames in natural order without hardcoded frame count',
        () async {
      final service = ScriptRecastParserService();

      final script = await service.parseDirectory(
        Directory('test/fixtures/script_recast/v4_slotted'),
      );

      expect(script.name, 'v4_slotted');
      expect(script.frames.map((frame) => frame.fileName), [
        'nai_1.json',
        'nai_2.json',
      ]);
      expect(script.detectedSchema, ScriptSchema.v4Slotted);
      expect(
        script.frames.every(
          (frame) => frame.parseStatus == ScriptFrameParseStatus.parsed,
        ),
        isTrue,
      );
      expect(script.id, startsWith('script-v4-slotted-'));
      expect(script.id, isNot(contains(RegExp(r'[\\/:]'))));
    });

    test('scans p-numbered json frames in natural order', () async {
      final service = ScriptRecastParserService();
      final directory = await Directory.systemTemp.createTemp(
        'script-recast-p-numbered-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File('test/fixtures/script_recast/v4_slotted/nai_2.json')
          .copy('${directory.path}/p001.json');
      await File('test/fixtures/script_recast/v4_slotted/nai_1.json')
          .copy('${directory.path}/p000.json');
      await File('${directory.path}/p000.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png preview 0'}),
      );
      await File('${directory.path}/p001.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png preview 1'}),
      );

      final script = await service.parseDirectory(directory);

      expect(script.frames.map((frame) => frame.fileName), [
        'p000.json',
        'p001.json',
      ]);
      expect(script.frames, hasLength(2));
      expect(script.frames.first.index, 1);
      expect(script.frames.first.sourceImagePath,
          endsWith('${Platform.pathSeparator}p000.png'));
      expect(script.detectedSchema, ScriptSchema.v4Slotted);
      expect(script.parseWarnings, isEmpty);
    });

    test('scans prompt-bearing json files in sparse numeric order', () async {
      final service = ScriptRecastParserService();
      final directory = await Directory.systemTemp.createTemp(
        'script-recast-sparse-json-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File('${directory.path}/shot_10.json').writeAsString(
        jsonEncode({'Description': 'artist:ten, rooftop'}),
      );
      await File('${directory.path}/shot_1.json').writeAsString(
        jsonEncode({'Description': 'artist:one, garden'}),
      );
      await File('${directory.path}/shot_4.json').writeAsString(
        jsonEncode({'Description': 'artist:four, library'}),
      );
      await File('${directory.path}/shot_6.json').writeAsString(
        jsonEncode({'width': 1024, 'height': 1024}),
      );

      final script = await service.parseDirectory(directory);

      expect(script.frames.map((frame) => frame.fileName), [
        'shot_1.json',
        'shot_4.json',
        'shot_10.json',
      ]);
      expect(script.frames.map((frame) => frame.index), [1, 2, 3]);
      expect(script.frames.map((frame) => frame.parsed.baseCaption), [
        'artist:one, garden',
        'artist:four, library',
        'artist:ten, rooftop',
      ]);
    });

    test('uses png metadata when json and png counts differ', () async {
      final service = ScriptRecastParserService();
      final directory = await Directory.systemTemp.createTemp(
        'script-recast-json-png-priority-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File('${directory.path}/frame_001.json').writeAsString(
        jsonEncode({'Description': 'artist:json, moonlit room'}),
      );
      await File('${directory.path}/frame_001.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png, should be ignored'}),
      );
      await File('${directory.path}/frame_004.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png-only, rainy street'}),
      );

      final script = await service.parseDirectory(directory);

      expect(script.frames.map((frame) => frame.fileName), [
        'frame_001.png',
        'frame_004.png',
      ]);
      expect(script.frames.map((frame) => frame.index), [1, 2]);
      expect(script.frames.first.sourcePath,
          endsWith('${Platform.pathSeparator}frame_001.png'));
      expect(script.frames.first.sourceImagePath,
          endsWith('${Platform.pathSeparator}frame_001.png'));
      expect(script.frames.last.sourceImagePath,
          endsWith('${Platform.pathSeparator}frame_004.png'));
      expect(script.frames.first.parsed.baseCaption, contains('artist:png'));
      expect(
          script.frames.last.parsed.baseCaption, contains('artist:png-only'));
    });

    test('uses png metadata when json and png stems differ', () async {
      final service = ScriptRecastParserService();
      final directory = await Directory.systemTemp.createTemp(
        'script-recast-numeric-pairing-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File('${directory.path}/scene_001.json').writeAsString(
        jsonEncode({'Description': 'artist:json-a, first scene'}),
      );
      await File('${directory.path}/render_001.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png-a, preview only'}),
      );
      await File('${directory.path}/scene_002.json').writeAsString(
        jsonEncode({'Description': 'artist:json-b, second scene'}),
      );
      await File('${directory.path}/render_002.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png-b, preview only'}),
      );

      final script = await service.parseDirectory(directory);

      expect(script.frames.map((frame) => frame.fileName), [
        'render_001.png',
        'render_002.png',
      ]);
      expect(
        script.frames.first.parsed.baseCaption,
        contains('artist:png-a'),
      );
    });

    test('uses png metadata instead of natural-order json pairing', () async {
      final service = ScriptRecastParserService();
      final directory = await Directory.systemTemp.createTemp(
        'script-recast-natural-pairing-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File('${directory.path}/alpha.json').writeAsString(
        jsonEncode({'Description': 'artist:json-a, alpha scene'}),
      );
      await File('${directory.path}/cover-a.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png-a, preview only'}),
      );
      await File('${directory.path}/beta.json').writeAsString(
        jsonEncode({'Description': 'artist:json-b, beta scene'}),
      );
      await File('${directory.path}/cover-b.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png-b, preview only'}),
      );

      final script = await service.parseDirectory(directory);

      expect(script.frames.map((frame) => frame.fileName), [
        'cover-a.png',
        'cover-b.png',
      ]);
      expect(script.frames.first.parsed.baseCaption, contains('artist:png-a'));
    });

    test('parses png frames through file metadata fast path', () async {
      final metadataService = _FileOnlyMetadataImportService();
      final service = ScriptRecastParserService(
        metadataImportService: metadataService,
      );
      final directory = await Directory.systemTemp.createTemp(
        'script-recast-png-file-fast-path-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File('${directory.path}/p000.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png, file fast path'}),
      );

      final script = await service.parseDirectory(directory);

      expect(metadataService.parseFileCalls, 1);
      expect(metadataService.parseBytesCalls, 0);
      expect(script.frames, hasLength(1));
      expect(script.frames.single.fileName, 'p000.png');
      expect(script.frames.single.parsed.baseCaption,
          'artist:png, file fast path');
    });

    test('reports discovery and per-frame parsing progress', () async {
      final service = ScriptRecastParserService();
      final directory = await Directory.systemTemp.createTemp(
        'script-recast-progress-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File('${directory.path}/p000.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png, progress 0'}),
      );
      await File('${directory.path}/p001.png').writeAsBytes(
        _pngWithTextChunk({'Description': 'artist:png, progress 1'}),
      );
      final events = <ScriptRecastParseProgress>[];

      final script = await service.parseDirectory(
        directory,
        onProgress: events.add,
      );

      expect(script.frames, hasLength(2));
      expect(
          events.map((event) => event.phase),
          containsAllInOrder([
            ScriptRecastParseProgressPhase.scanning,
            ScriptRecastParseProgressPhase.sourcesDiscovered,
            ScriptRecastParseProgressPhase.sourceParsing,
            ScriptRecastParseProgressPhase.sourceParsed,
            ScriptRecastParseProgressPhase.sourceParsing,
            ScriptRecastParseProgressPhase.sourceParsed,
            ScriptRecastParseProgressPhase.complete,
          ]));
      final discovered = events.firstWhere(
        (event) =>
            event.phase == ScriptRecastParseProgressPhase.sourcesDiscovered,
      );
      expect(discovered.totalSources, 2);
      expect(discovered.visitedSources, 0);
      final parsedEvents = events
          .where((event) =>
              event.phase == ScriptRecastParseProgressPhase.sourceParsed)
          .toList(growable: false);
      expect(parsedEvents.map((event) => event.visitedSources), [1, 2]);
      expect(parsedEvents.map((event) => event.parsedFrames), [1, 2]);
      expect(parsedEvents.last.fraction, 1);
      expect(events.last.phase, ScriptRecastParseProgressPhase.complete);
      expect(events.last.totalSources, 2);
      expect(events.last.parsedFrames, 2);
    });

    test('extracts parsed frame prompt, negative, coords, seed and source',
        () async {
      final service = ScriptRecastParserService();

      final script = await service.parseDirectory(
        Directory('test/fixtures/script_recast/v4_slotted'),
      );
      final frame = script.frames.first;

      expect(frame.parsed.baseCaption, contains('city lights'));
      expect(frame.parsed.charCaptions, hasLength(2));
      expect(frame.parsed.negativeBase, contains('lowres'));
      expect(frame.parsed.negativeCharCaptions, ['bad hands']);
      expect(frame.parsed.coords, [
        const RecastPoint(x: 0.25, y: 0.55),
        const RecastPoint(x: 0.75, y: 0.45),
      ]);
      expect(frame.parsed.generationParams['seed'], 123456);
      expect(frame.parsed.generationParams['sampler'], 'k_euler_ancestral');
      expect(frame.parsed.sourcePayload['Comment'], isNotNull);
    });

    test('detects base inline and mixed schemas by frame voting', () async {
      final service = ScriptRecastParserService();

      final inline = await service.parseDirectory(
        Directory('test/fixtures/script_recast/base_inline'),
      );
      final mixed = await service.parseDirectory(
        Directory('test/fixtures/script_recast/mixed'),
      );

      expect(inline.detectedSchema, ScriptSchema.baseInline);
      expect(mixed.detectedSchema, ScriptSchema.v4Partial);
    });

    test('marks broken frames as error without aborting the script', () async {
      final service = ScriptRecastParserService();

      final script = await service.parseDirectory(
        Directory('test/fixtures/script_recast/broken'),
      );

      expect(script.frames, hasLength(2));
      expect(script.frames.first.parseStatus, ScriptFrameParseStatus.error);
      expect(script.frames.first.warnings, isNotEmpty);
      expect(script.frames.last.parseStatus, ScriptFrameParseStatus.parsed);
    });

    test('warns when directory contains no script frames', () async {
      final service = ScriptRecastParserService();
      final directory = await Directory.systemTemp.createTemp(
        'script-recast-empty-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File('${directory.path}/notes.json').writeAsString('{}');

      final script = await service.parseDirectory(directory);

      expect(script.frames, isEmpty);
      expect(script.parseWarnings.single, contains('prompt-bearing JSON'));
      expect(script.parseWarnings.single, contains('PNG'));
      expect(script.meta['frameCount'], 0);
    });

    test('marks unreadable frame text as error without aborting the script',
        () async {
      final service = ScriptRecastParserService();
      final directory = await Directory.systemTemp.createTemp(
        'script-recast-unreadable-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File('${directory.path}/nai_1.json').writeAsBytes([0xff]);
      await File('${directory.path}/nai_2.json').writeAsString(
        '{"Description":"safe frame"}',
      );

      final script = await service.parseDirectory(directory);

      expect(script.frames, hasLength(2));
      expect(script.frames.first.parseStatus, ScriptFrameParseStatus.error);
      expect(script.frames.first.rawJson, isEmpty);
      expect(
        script.frames.first.warnings.single,
        contains('Malformed JSON or text encoding'),
      );
      expect(script.frames.last.parseStatus, ScriptFrameParseStatus.parsed);
    });

    test('parsing is stable across two runs', () async {
      final service = ScriptRecastParserService();

      final first = await service.parseDirectory(
        Directory('test/fixtures/script_recast/v4_slotted'),
      );
      final second = await service.parseDirectory(
        Directory('test/fixtures/script_recast/v4_slotted'),
      );

      expect(first.toJson(), second.toJson());
    });
  });
}

class _FileOnlyMetadataImportService extends WorkbenchMetadataImportService {
  var parseFileCalls = 0;
  var parseBytesCalls = 0;

  @override
  Future<NaiMetadataParseResult> parseFile(File file) async {
    parseFileCalls++;
    return NaiMetadataParser.parseMap({
      'Description': 'artist:png, file fast path',
    });
  }

  @override
  Future<NaiMetadataParseResult> parseBytes(
    String fileName,
    Uint8List bytes,
  ) async {
    parseBytesCalls++;
    throw StateError('Directory PNG import should use parseFile.');
  }
}

Uint8List _pngWithTextChunk(Map<String, dynamic> metadata) {
  final bytes = BytesBuilder();
  bytes.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  bytes.add(_pngChunk(
    'IHDR',
    Uint8List.fromList([
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      2,
      0,
      0,
      0,
    ]),
  ));
  for (final entry in metadata.entries) {
    bytes.add(_pngChunk(
      'tEXt',
      Uint8List.fromList([
        ...utf8.encode(entry.key),
        0,
        ...utf8.encode(
          entry.value is String
              ? entry.value as String
              : jsonEncode(entry.value),
        ),
      ]),
    ));
  }
  bytes.add(_pngChunk('IEND', Uint8List(0)));
  return bytes.toBytes();
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  return Uint8List.fromList([
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(_crc32([...typeBytes, ...data])),
  ]);
}

Uint8List _uint32(int value) {
  final data = ByteData(4)..setUint32(0, value);
  return data.buffer.asUint8List();
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var index = 0; index < 8; index += 1) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
