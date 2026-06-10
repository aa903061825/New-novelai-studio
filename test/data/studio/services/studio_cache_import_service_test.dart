import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/services/studio_cache_import_service.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('studio-cache-import-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('imports a nested bundled cache folder into the workspace', () async {
    final packageRoot = Directory('${tempDir.path}/package');
    final source = Directory('${packageRoot.path}/bundled_cache/novel_studio');
    final target = Directory('${tempDir.path}/target');
    await _writeText(
      source,
      WorkspacePaths.manifest,
      '{"name":"Shared Studio","schemaVersion":1}',
    );
    await _writeText(
      source,
      WorkspacePaths.characters,
      '[{"id":"char-1","name":"Shared Character","traits":{}}]',
    );
    await _writeText(
      source,
      WorkspacePaths.scriptRecastCacheFile('script-1'),
      '{"scriptId":"script-1","status":"ready"}',
    );
    await _writeText(source, 'savedbox.hive', 'personal token data');
    await _writeText(source, 'output/nai/generated.png', 'generated output');

    final service = StudioCacheImportService();
    final result = await service.importFromDirectory(
      packageRoot,
      targetRoot: target,
    );

    expect(result.importedFiles, 3);
    expect(result.backupPath, isNull);
    expect(
      await File('${target.path}/${WorkspacePaths.characters}').readAsString(),
      contains('Shared Character'),
    );
    expect(
      await File(
        '${target.path}/${WorkspacePaths.scriptRecastCacheFile('script-1')}',
      ).exists(),
      isTrue,
    );
    expect(await File('${target.path}/savedbox.hive').exists(), isFalse);
    expect(await File('${target.path}/output/nai/generated.png').exists(),
        isFalse);
  });

  test('imports a zip cache package and backs up an existing workspace',
      () async {
    final target = Directory('${tempDir.path}/target');
    await _writeText(
      target,
      WorkspacePaths.manifest,
      '{"name":"Existing Studio","schemaVersion":1}',
    );
    await _writeText(
      target,
      WorkspacePaths.characters,
      '[{"id":"old","name":"Old Character","traits":{}}]',
    );
    final zipFile = File('${tempDir.path}/cache.zip');
    await zipFile.writeAsBytes(
      _zipBytes({
        'nai-new-cache/appdata-roaming/org.exception0x0194/nai3_autodraw/'
                'novel_studio/${WorkspacePaths.manifest}':
            '{"name":"Shared Studio","schemaVersion":1}',
        'nai-new-cache/appdata-roaming/org.exception0x0194/nai3_autodraw/'
                'novel_studio/${WorkspacePaths.characters}':
            '[{"id":"new","name":"New Character","traits":{}}]',
      }),
    );

    final service = StudioCacheImportService(
      clock: () => DateTime.utc(2026, 6, 9, 12, 30),
    );
    final result = await service.importFromZip(
      zipFile,
      targetRoot: target,
    );

    expect(result.backupPath, isNotNull);
    expect(await Directory(result.backupPath!).exists(), isTrue);
    expect(
      await File('${result.backupPath!}/${WorkspacePaths.characters}')
          .readAsString(),
      contains('Old Character'),
    );
    expect(
      await File('${target.path}/${WorkspacePaths.characters}').readAsString(),
      contains('New Character'),
    );
  });
}

Future<void> _writeText(
  Directory root,
  String relativePath,
  String content,
) async {
  final file = File('${root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

List<int> _zipBytes(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive)!;
}
