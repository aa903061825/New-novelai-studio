import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

import '../../tool/import_script_recast_image_set_caches.dart';

void main() {
  group('importScriptRecastImageSetCaches', () {
    late Directory sourceRoot;
    late Directory workspaceRoot;

    setUp(() async {
      sourceRoot = await Directory.systemTemp.createTemp(
        'script-recast-image-set-source-',
      );
      workspaceRoot = await Directory.systemTemp.createTemp(
        'script-recast-image-set-workspace-',
      );
    });

    tearDown(() async {
      if (await sourceRoot.exists()) {
        await sourceRoot.delete(recursive: true);
      }
      if (await workspaceRoot.exists()) {
        await workspaceRoot.delete(recursive: true);
      }
    });

    test('writes one cache for each prompt-bearing child script directory',
        () async {
      final first = Directory('${sourceRoot.path}${Platform.pathSeparator}a');
      final second = Directory('${sourceRoot.path}${Platform.pathSeparator}b');
      final empty =
          Directory('${sourceRoot.path}${Platform.pathSeparator}empty');
      await first.create();
      await second.create();
      await empty.create();
      await File('${first.path}${Platform.pathSeparator}p1.json')
          .writeAsString(jsonEncode({'Description': 'artist:first, garden'}));
      await File('${second.path}${Platform.pathSeparator}p1.json')
          .writeAsString(jsonEncode({'Description': 'artist:second, street'}));
      await File('${empty.path}${Platform.pathSeparator}notes.json')
          .writeAsString('{}');

      final service = WorkspaceService();
      await service.createWorkspace(workspaceRoot.path);

      final report = await importScriptRecastImageSetCaches(
        sourceRoot: sourceRoot.path,
        workspaceRoot: workspaceRoot.path,
      );
      final caches = await service.loadRecastScriptCaches();

      expect(report.written, 2);
      expect(report.skipped, 1);
      expect(report.rows.where((row) => row.preservedAiDraft), isEmpty);
      expect(caches.map((cache) => cache.scriptName).toSet(), {'a', 'b'});
      expect(
        caches.map((cache) => cache.scriptSnapshot['frames']).whereType<List>(),
        everyElement(hasLength(1)),
      );
    });
  });
}
