import 'dart:io';

import 'package:archive/archive.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';

class StudioCacheImportResult {
  final String sourcePath;
  final String targetPath;
  final int importedFiles;
  final String? backupPath;

  const StudioCacheImportResult({
    required this.sourcePath,
    required this.targetPath,
    required this.importedFiles,
    this.backupPath,
  });
}

class StudioCacheImportService {
  final DateTime Function() clock;

  const StudioCacheImportService({
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  Directory defaultBundledCacheRoot() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    return Directory(
      '${exeDir.path}${Platform.pathSeparator}bundled_cache',
    );
  }

  Future<StudioCacheImportResult?> autoImportBundledCache({
    required Directory targetRoot,
    Directory? bundledCacheRoot,
  }) async {
    if (await _hasManifest(targetRoot)) {
      return null;
    }
    final sourceRoot = bundledCacheRoot ?? defaultBundledCacheRoot();
    if (!await sourceRoot.exists()) {
      return null;
    }
    return importFromDirectory(
      sourceRoot,
      targetRoot: targetRoot,
      createBackup: false,
    );
  }

  Future<StudioCacheImportResult> importFromDirectory(
    Directory packageRoot, {
    required Directory targetRoot,
    bool createBackup = true,
  }) async {
    final sourceRoot = await _findWorkspaceRoot(packageRoot);
    if (sourceRoot == null) {
      throw const FormatException(
        'Cache package does not contain a Novel Studio workspace manifest.',
      );
    }

    String? backupPath;
    if (createBackup && await _hasManifest(targetRoot)) {
      final backupRoot = await _backupWorkspace(targetRoot);
      backupPath = backupRoot.path;
    }

    await targetRoot.create(recursive: true);
    var importedFiles = 0;
    await for (final entity in sourceRoot.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final relativePath = _relativePath(sourceRoot, entity);
      if (!_shouldImportWorkspaceFile(relativePath)) {
        continue;
      }
      final targetFile = File(
        '${targetRoot.path}${Platform.pathSeparator}$relativePath',
      );
      await targetFile.parent.create(recursive: true);
      await entity.copy(targetFile.path);
      importedFiles += 1;
    }

    if (!await _hasManifest(targetRoot)) {
      throw const FormatException(
        'Cache import did not produce a valid workspace manifest.',
      );
    }

    return StudioCacheImportResult(
      sourcePath: sourceRoot.path,
      targetPath: targetRoot.path,
      importedFiles: importedFiles,
      backupPath: backupPath,
    );
  }

  Future<StudioCacheImportResult> importFromZip(
    File zipFile, {
    required Directory targetRoot,
    bool createBackup = true,
  }) async {
    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    final workspacePrefix = _findArchiveWorkspacePrefix(archive);
    if (workspacePrefix == null) {
      throw const FormatException(
        'Cache package does not contain a Novel Studio workspace manifest.',
      );
    }

    String? backupPath;
    if (createBackup && await _hasManifest(targetRoot)) {
      final backupRoot = await _backupWorkspace(targetRoot);
      backupPath = backupRoot.path;
    }

    await targetRoot.create(recursive: true);
    var importedFiles = 0;
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final segments = _safeArchiveSegments(file.name);
      if (segments == null || !_startsWithSegments(segments, workspacePrefix)) {
        continue;
      }
      final relativeSegments = segments.sublist(workspacePrefix.length);
      if (relativeSegments.isEmpty) {
        continue;
      }
      final relativePath = relativeSegments.join(Platform.pathSeparator);
      if (!_shouldImportWorkspaceFile(relativePath)) {
        continue;
      }
      final target = File(
        '${targetRoot.path}${Platform.pathSeparator}$relativePath',
      );
      await target.parent.create(recursive: true);
      await target.writeAsBytes(file.content as List<int>, flush: false);
      importedFiles += 1;
    }

    if (!await _hasManifest(targetRoot)) {
      throw const FormatException(
        'Cache import did not produce a valid workspace manifest.',
      );
    }

    return StudioCacheImportResult(
      sourcePath: '${zipFile.path}#${workspacePrefix.join('/')}',
      targetPath: targetRoot.path,
      importedFiles: importedFiles,
      backupPath: backupPath,
    );
  }

  Future<Directory?> _findWorkspaceRoot(Directory packageRoot) async {
    final directCandidates = [
      packageRoot,
      Directory(
        '${packageRoot.path}${Platform.pathSeparator}novel_studio',
      ),
      Directory(
        '${packageRoot.path}${Platform.pathSeparator}bundled_cache'
        '${Platform.pathSeparator}novel_studio',
      ),
      Directory(
        '${packageRoot.path}${Platform.pathSeparator}appdata-roaming'
        '${Platform.pathSeparator}novel_studio',
      ),
      Directory(
        '${packageRoot.path}${Platform.pathSeparator}appdata-roaming'
        '${Platform.pathSeparator}Novel Studio'
        '${Platform.pathSeparator}Novel Studio'
        '${Platform.pathSeparator}novel_studio',
      ),
      Directory(
        '${packageRoot.path}${Platform.pathSeparator}novel-studio-cache'
        '${Platform.pathSeparator}appdata-roaming'
        '${Platform.pathSeparator}Novel Studio'
        '${Platform.pathSeparator}Novel Studio'
        '${Platform.pathSeparator}novel_studio',
      ),
    ];
    for (final candidate in directCandidates) {
      if (await _hasManifest(candidate)) {
        return candidate;
      }
    }
    if (!await packageRoot.exists()) {
      return null;
    }
    await for (final entity in packageRoot.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      if (_fileName(entity.path) == WorkspacePaths.manifest) {
        return entity.parent;
      }
    }
    return null;
  }

  Future<Directory> _backupWorkspace(Directory targetRoot) async {
    final stamp = _timestamp(clock().toUtc());
    final parent = targetRoot.parent;
    var backupRoot = Directory('${targetRoot.path}-backup-$stamp');
    var suffix = 1;
    while (await backupRoot.exists()) {
      backupRoot = Directory('${targetRoot.path}-backup-$stamp-$suffix');
      suffix += 1;
    }
    await backupRoot.create(recursive: true);
    await for (final entity in targetRoot.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final relativePath = _relativePath(targetRoot, entity);
      final backupFile = File(
        '${backupRoot.path}${Platform.pathSeparator}$relativePath',
      );
      await backupFile.parent.create(recursive: true);
      await entity.copy(backupFile.path);
    }
    // Touch the parent so Explorer sorts the backup near the workspace folder.
    await parent.stat();
    return backupRoot;
  }

  Future<bool> _hasManifest(Directory root) {
    return File(
      '${root.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
    ).exists();
  }

  bool _shouldImportWorkspaceFile(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/').toLowerCase();
    final segments = normalized.split('/');
    if (segments.any((segment) => segment == '..' || segment.isEmpty)) {
      return false;
    }
    if (segments.first == 'output' || segments.first == 'imports') {
      return false;
    }
    if (segments.any((segment) => segment == '.git')) {
      return false;
    }
    if (normalized.endsWith('.lock') ||
        normalized.endsWith('.hive') ||
        normalized.endsWith('.log') ||
        normalized.endsWith('.tmp')) {
      return false;
    }
    if (segments.any((segment) =>
        segment.contains('token') ||
        segment.contains('secret') ||
        segment.contains('credential') ||
        segment.contains('password'))) {
      return false;
    }
    if (segments.last == 'secrets.json' ||
        segments.last == 'savedbox.hive' ||
        segments.last == 'savedbox.lock') {
      return false;
    }
    return true;
  }

  List<String>? _findArchiveWorkspacePrefix(Archive archive) {
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final segments = _safeArchiveSegments(file.name);
      if (segments == null ||
          segments.isEmpty ||
          segments.last != WorkspacePaths.manifest) {
        continue;
      }
      final prefix = segments.sublist(0, segments.length - 1);
      if (prefix.isNotEmpty && prefix.last == 'novel_studio') {
        return prefix;
      }
    }
    return null;
  }

  bool _startsWithSegments(List<String> segments, List<String> prefix) {
    if (segments.length < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i += 1) {
      if (segments[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  List<String>? _safeArchiveSegments(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty ||
        segments.any((segment) => segment == '.' || segment == '..')) {
      return null;
    }
    return segments;
  }

  String _relativePath(Directory root, File file) {
    final rootPath = root.absolute.path;
    final filePath = file.absolute.path;
    return filePath.substring(rootPath.length + 1);
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  String _timestamp(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}${two(dateTime.month)}${two(dateTime.day)}-'
        '${two(dateTime.hour)}${two(dateTime.minute)}${two(dateTime.second)}';
  }
}
