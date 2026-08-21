import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:novel_studio/data/studio/services/script_role_mapping_profile_service.dart';
import 'package:uuid/uuid.dart';

Future<void> main(List<String> arguments) async {
  final options = _parseOptions(arguments);
  final cacheFile = File(_requiredOption(options, 'cache'));
  final libraryFile = File(_requiredOption(options, 'library'));
  final sourceRoleId = _requiredOption(options, 'role');
  final name = _requiredOption(options, 'name').trim();
  final characterName = (options['character-name'] ?? '').trim();

  if (!await cacheFile.exists()) {
    throw FileSystemException('剧本缓存不存在', cacheFile.path);
  }
  if (name.isEmpty) {
    throw const FormatException('角色缓存名称不能为空。');
  }

  final decoded = jsonDecode(await cacheFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('剧本缓存必须是 JSON 对象。');
  }
  final cache = RecastScriptCache.fromJson(
    Map<String, dynamic>.from(decoded),
  );
  final replacement = cache.mapping.rolePromptReplacements
      .where((entry) => entry.sourceRoleId == sourceRoleId)
      .firstOrNull;
  if (replacement == null) {
    throw StateError('剧本缓存中不存在角色：$sourceRoleId');
  }

  const service = ScriptRoleMappingProfileService();
  final now = DateTime.now().toUtc();
  final profile = service.createProfile(
    id: const Uuid().v4(),
    name: name,
    replacement: replacement,
    targetCharacterNameSnapshot: characterName,
    now: now,
  );
  if (profile.blocks.isEmpty) {
    throw StateError('角色“${replacement.displayLabel}”没有有效映射，未创建空缓存。');
  }

  final current = await _loadLibrary(libraryFile);
  String? backupPath;
  if (await libraryFile.exists()) {
    final timestamp = now
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '');
    backupPath = '${libraryFile.path}.backup-$timestamp';
    await libraryFile.copy(backupPath);
  }

  try {
    final normalizedName = name.toLowerCase();
    if (current.profiles.any(
      (entry) => entry.name.trim().toLowerCase() == normalizedName,
    )) {
      throw FormatException('角色缓存名称已存在：$name');
    }
    await _saveLibraryAtomically(
      libraryFile,
      current.copyWith(
        profiles: List.unmodifiable([...current.profiles, profile]),
      ),
    );
  } catch (_) {
    if (backupPath != null) {
      stderr.writeln('写入失败；原总库备份保留在：$backupPath');
    }
    rethrow;
  }

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'library': libraryFile.path,
      if (backupPath != null) 'backup': backupPath,
      'profileId': profile.id,
      'profileName': profile.name,
      'sourceScript': cache.scriptName,
      'sourceRoleId': replacement.sourceRoleId,
      'sourceRoleLabel': replacement.displayLabel,
      'targetCharacterId': profile.targetCharacterId,
      'targetCharacterNameSnapshot': profile.targetCharacterNameSnapshot,
      'targetIdentityPrompt': profile.targetIdentityPrompt,
      'blockCount': profile.blocks.length,
      'termCount': profile.blocks.expand((block) => block.terms).length,
    }),
  );
}

Map<String, String> _parseOptions(List<String> arguments) {
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (!argument.startsWith('--') || index + 1 >= arguments.length) {
      throw FormatException('无效参数：$argument');
    }
    result[argument.substring(2)] = arguments[index + 1];
    index += 1;
  }
  return result;
}

String _requiredOption(Map<String, String> options, String name) {
  final value = options[name]?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('缺少参数：--$name');
  }
  return value;
}

Future<RoleMappingProfileLibrary> _loadLibrary(File file) async {
  if (!await file.exists()) return const RoleMappingProfileLibrary();
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw const FormatException('角色映射缓存总库必须是 JSON 对象。');
  }
  return RoleMappingProfileLibrary.fromJson(
    Map<String, dynamic>.from(decoded),
  );
}

Future<void> _saveLibraryAtomically(
  File target,
  RoleMappingProfileLibrary library,
) async {
  validateRoleMappingProfileNames(library.profiles);
  await target.parent.create(recursive: true);
  final temporary = File(
    '${target.path}.tmp-${DateTime.now().toUtc().microsecondsSinceEpoch}',
  );
  try {
    const encoder = JsonEncoder.withIndent('  ');
    await temporary.writeAsString('${encoder.convert(library.toJson())}\n');
    await temporary.rename(target.path);
  } catch (_) {
    if (await temporary.exists()) {
      await temporary.delete();
    }
    rethrow;
  }
}
