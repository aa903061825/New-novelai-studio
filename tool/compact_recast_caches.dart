import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/compact_recast_caches.dart '
      '<workspace root> [--backup]',
    );
    exitCode = 64;
    return;
  }

  final workspaceRoot = Directory(args.first);
  if (!await workspaceRoot.exists()) {
    stderr.writeln('Workspace does not exist: ${workspaceRoot.path}');
    exitCode = 66;
    return;
  }

  final cacheDirectory = Directory(
    [
      workspaceRoot.path,
      ...WorkspacePaths.scriptRecastCacheDir.split('/'),
    ].join(Platform.pathSeparator),
  );
  if (!await cacheDirectory.exists()) {
    stdout.writeln(
      jsonEncode({
        'workspace': workspaceRoot.path,
        'cacheDirectory': cacheDirectory.path,
        'files': 0,
        'beforeBytes': 0,
        'afterBytes': 0,
        'savedBytes': 0,
      }),
    );
    return;
  }

  final backup = args.contains('--backup')
      ? Directory(
          [
            workspaceRoot.path,
            'script_recast',
            'cache-backup-${_timestamp()}-compact-recast-caches',
          ].join(Platform.pathSeparator),
        )
      : null;
  final beforeFiles = await _jsonFiles(cacheDirectory);
  final beforeBytes = await _totalBytes(beforeFiles);
  if (backup != null) {
    await backup.create(recursive: true);
    for (final file in beforeFiles) {
      await file.copy('${backup.path}${Platform.pathSeparator}${_name(file)}');
    }
  }

  final service = WorkspaceService();
  await service.openWorkspace(workspaceRoot.path);
  final caches = await service.loadRecastScriptCaches();

  final afterFiles = await _jsonFiles(cacheDirectory);
  final afterBytes = await _totalBytes(afterFiles);
  stdout.writeln(
    jsonEncode({
      'workspace': workspaceRoot.path,
      'cacheDirectory': cacheDirectory.path,
      'files': beforeFiles.length,
      'cachesLoaded': caches.length,
      'beforeBytes': beforeBytes,
      'afterBytes': afterBytes,
      'savedBytes': beforeBytes - afterBytes,
      if (backup != null) 'backup': backup.path,
    }),
  );
}

Future<List<File>> _jsonFiles(Directory directory) async {
  final files = await directory
      .list()
      .where((entry) => entry is File && entry.path.endsWith('.json'))
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

Future<int> _totalBytes(List<File> files) async {
  var total = 0;
  for (final file in files) {
    total += await file.length();
  }
  return total;
}

String _timestamp() {
  final now = DateTime.now().toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

String _name(File file) => file.uri.pathSegments.last;
