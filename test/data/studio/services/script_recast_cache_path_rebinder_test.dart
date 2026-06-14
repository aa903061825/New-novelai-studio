import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_recast_cache_path_rebinder.dart';
import 'package:nai_casrand/data/studio/services/script_recast_parser_service.dart';

void main() {
  test('rebinds cached script frame paths to the current import directory',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-cache-rebind-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final importDir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}Moved Story',
    );
    await importDir.create(recursive: true);
    final jsonFile = File(
      '${importDir.path}${Platform.pathSeparator}nai_1.json',
    );
    final imageFile = File(
      '${importDir.path}${Platform.pathSeparator}nai_1.png',
    );
    await jsonFile.writeAsString('{"Description":"blue eyes"}');
    await imageFile.writeAsBytes(const [137, 80, 78, 71]);

    final cached = Script(
      id: 'script-old-path',
      name: 'Moved Story',
      rootPath: r'E:\old-root\Moved Story',
      frames: const [
        ScriptFrame(
          index: 1,
          fileName: 'nai_1.json',
          sourcePath: r'E:\old-root\Moved Story\nai_1.json',
          sourceImagePath: r'E:\old-root\Moved Story\nai_1.png',
          rawJson: '{"Description":"blue eyes"}',
          parsed: ParsedFrame(baseCaption: 'blue eyes'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
      detectedSchema: ScriptSchema.baseInline,
    );

    final rebound = rebindCachedScriptToImportDirectory(
      cached,
      importDir,
    );

    expect(
      rebound.id,
      ScriptRecastParserService.scriptIdForDirectory(importDir),
    );
    expect(rebound.rootPath, importDir.path);
    expect(rebound.frames.single.sourcePath, jsonFile.path);
    expect(rebound.frames.single.sourceImagePath, imageFile.path);
  });
}
