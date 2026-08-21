import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:path_provider/path_provider.dart';

typedef RoleMappingProfileSupportDirectoryProvider = Future<Directory>
    Function();
typedef RoleMappingProfileAtomicCommitter = Future<void> Function(
  File source,
  String targetPath,
);

const _renameRetryDelays = [
  Duration(milliseconds: 30),
  Duration(milliseconds: 90),
  Duration(milliseconds: 180),
];

class RoleMappingProfileRepository {
  final File? fileOverride;
  final RoleMappingProfileSupportDirectoryProvider supportDirectoryProvider;
  final RoleMappingProfileAtomicCommitter atomicCommitter;

  Future<void>? _writeTail;

  RoleMappingProfileRepository({
    this.fileOverride,
    RoleMappingProfileSupportDirectoryProvider? supportDirectoryProvider,
    RoleMappingProfileAtomicCommitter? atomicCommitter,
  })  : supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory,
        atomicCommitter =
            atomicCommitter ?? _renameFileWithTransientAccessRetries;

  Future<File> resolveFile() async {
    final override = fileOverride;
    if (override != null) return override;
    final supportDirectory = await supportDirectoryProvider();
    return File(
      '${supportDirectory.path}${Platform.pathSeparator}novel_studio'
      '${Platform.pathSeparator}global'
      '${Platform.pathSeparator}role_mapping_profiles.json',
    );
  }

  Future<RoleMappingProfileLibrary> load() async {
    final pending = _writeTail;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // A failed save must not make the last valid file unreadable.
      }
    }
    return _loadNow();
  }

  Future<void> save(RoleMappingProfileLibrary library) async {
    await _enqueueWrite(() async {
      final file = await resolveFile();
      if (await file.exists()) {
        // Never let an unconditional save hide a corrupted or newer library.
        await _loadNow();
      }
      await _saveNow(library);
    });
  }

  Future<RoleMappingProfileLibrary> update(
    RoleMappingProfileLibrary Function(RoleMappingProfileLibrary current)
        transform,
  ) {
    final completer = Completer<RoleMappingProfileLibrary>();
    unawaited(
      _enqueueWrite(() async {
        final current = await _loadNow();
        final next = transform(current);
        await _saveNow(next);
        completer.complete(next);
      }).catchError((Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }),
    );
    return completer.future;
  }

  Future<void> _enqueueWrite(Future<void> Function() write) {
    final previous = _writeTail;
    final next = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // Later valid changes still get a chance to save.
        }
      }
      await write();
    }();
    _writeTail = next;
    return next.whenComplete(() {
      if (identical(_writeTail, next)) {
        _writeTail = null;
      }
    });
  }

  Future<RoleMappingProfileLibrary> _loadNow() async {
    final file = await resolveFile();
    if (!await file.exists()) {
      return const RoleMappingProfileLibrary();
    }
    final source = await file.readAsString();
    if (source.trim().isEmpty) {
      throw FormatException(
        'Role mapping profile library is empty: ${file.path}',
      );
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw FormatException(
        'Role mapping profile library must be a JSON object: ${file.path}',
      );
    }
    return RoleMappingProfileLibrary.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  Future<void> _saveNow(RoleMappingProfileLibrary library) async {
    validateRoleMappingProfileNames(library.profiles);
    final file = await resolveFile();
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp-${DateTime.now().toUtc().microsecondsSinceEpoch}',
    );
    try {
      const encoder = JsonEncoder.withIndent('  ');
      await temporary.writeAsString('${encoder.convert(library.toJson())}\n');
      await atomicCommitter(temporary, file.path);
    } catch (_) {
      try {
        if (await temporary.exists()) {
          await temporary.delete();
        }
      } on FileSystemException {
        // Preserve the original save error.
      }
      rethrow;
    }
  }
}

Future<void> _renameFileWithTransientAccessRetries(
  File source,
  String targetPath,
) async {
  for (var attempt = 0;; attempt += 1) {
    try {
      await source.rename(targetPath);
      return;
    } on FileSystemException catch (error) {
      if (!_isTransientRenameAccessDenied(error) ||
          attempt >= _renameRetryDelays.length) {
        rethrow;
      }
      await Future<void>.delayed(_renameRetryDelays[attempt]);
    }
  }
}

bool _isTransientRenameAccessDenied(FileSystemException error) {
  final errorCode = error.osError?.errorCode;
  if (errorCode == 5 || errorCode == 32) return true;
  final detail = [
    error.message,
    error.osError?.message,
  ].whereType<String>().join(' ').toLowerCase();
  return detail.contains('cannot rename') &&
      (detail.contains('access') ||
          detail.contains('denied') ||
          detail.contains('sharing violation') ||
          detail.contains('used by another process'));
}
