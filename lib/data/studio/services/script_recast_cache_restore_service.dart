import 'dart:io';

import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';

class ScriptRecastCacheRestoreService {
  const ScriptRecastCacheRestoreService();

  String sourceContentFingerprint(Script script) {
    final parts = [
      'schema:${script.detectedSchema.name}',
      'frames:${script.frames.length}',
      for (final frame in script.frames)
        '${frame.index}:${frame.fileName}:${_stableContentHash(frame.rawJson)}',
    ];
    return parts.join('|');
  }

  String sourceContentFingerprintFromSnapshot(
    Map<String, dynamic> scriptSnapshot,
  ) {
    if (scriptSnapshot.isEmpty) {
      return '';
    }
    try {
      return sourceContentFingerprint(Script.fromJson(scriptSnapshot));
    } catch (_) {
      return '';
    }
  }

  String sourceFingerprint(Script script) {
    final parts = [
      script.id,
      normalizeScriptPath(script.rootPath),
      for (final frame in script.frames)
        '${frame.index}:${frame.fileName}:'
            '${normalizeScriptPath(frame.sourcePath)}:'
            '${_stableContentHash(frame.rawJson)}',
    ];
    return parts.join('|');
  }

  bool cacheHasSourceContentFingerprint(
    RecastScriptCache cache,
    String sourceContentFingerprint,
  ) {
    if (sourceContentFingerprint.trim().isEmpty) {
      return false;
    }
    final cacheFingerprint = cache.sourceContentFingerprint.trim().isNotEmpty
        ? cache.sourceContentFingerprint
        : sourceContentFingerprintFromSnapshot(cache.scriptSnapshot);
    return cacheFingerprint.isNotEmpty &&
        cacheFingerprint == sourceContentFingerprint;
  }

  bool cacheBelongsToScript(RecastScriptCache cache, Script script) {
    return cache.scriptId == script.id ||
        sameScriptPath(cache.sourceRootPath, script.rootPath);
  }

  bool cacheMatchesImportPath(RecastScriptCache cache, String path) {
    return sameScriptPath(cache.sourceRootPath, path) ||
        sameScriptPath(cache.sourceRootPath, Directory(path).path) ||
        sameScriptPath(cache.sourceRootPath, Directory(path).absolute.path);
  }

  bool cacheNameMatchesImportPath(RecastScriptCache cache, String path) {
    final importName = normalizeScriptName(scriptPathLeaf(path));
    if (importName.isEmpty) {
      return false;
    }
    if (normalizeScriptName(scriptPathLeaf(cache.sourceRootPath)) !=
        importName) {
      return false;
    }
    return normalizeScriptName(cache.scriptName) == importName ||
        normalizeScriptName(cache.scriptSnapshot['name']?.toString() ?? '') ==
            importName;
  }

  bool cacheSnapshotHasFrames(Map<String, dynamic> scriptSnapshot) {
    final frames = scriptSnapshot['frames'];
    return frames is List && frames.isNotEmpty;
  }

  bool pathMayNeedAliasCacheFallback(String path) {
    return scriptPathLeaf(path).trim().isNotEmpty;
  }

  RecastScriptCache? bestExactCacheForScript(
    Iterable<RecastScriptCache> caches, {
    required Script script,
    required String sourceFingerprint,
  }) {
    return bestExactCache([
      for (final cache in caches)
        if (cacheBelongsToScript(cache, script) &&
            cache.sourceFingerprint == sourceFingerprint)
          cache,
    ]);
  }

  RecastScriptCache? bestExactCache(Iterable<RecastScriptCache> caches) {
    RecastScriptCache? best;
    for (final cache in caches) {
      if (best == null || isBetterCacheCandidate(cache, best)) {
        best = cache;
      }
    }
    return best;
  }

  bool isBetterCacheCandidate(
    RecastScriptCache candidate,
    RecastScriptCache current,
  ) {
    final candidateScore = cacheAiDraftScore(candidate);
    final currentScore = cacheAiDraftScore(current);
    if (candidateScore != currentScore) {
      return candidateScore > currentScore;
    }
    return candidate.updatedAt.isAfter(current.updatedAt);
  }

  int cacheAiDraftScore(RecastScriptCache cache) {
    final extraction = cache.aiRoleExtraction;
    if (extraction.isReady && extraction.roles.isNotEmpty) {
      return 3;
    }
    if (extraction.status != ScriptAiRoleExtractionStatus.idle) {
      return 2;
    }
    if (cache.aiRoleExtractionChunks.isNotEmpty) {
      return 1;
    }
    return 0;
  }

  RecastScriptCache cachePreservingExistingAiDraft(
    RecastScriptCache draft,
    RecastScriptCache? existing,
  ) {
    if (existing == null ||
        draft.aiRoleExtraction.status != ScriptAiRoleExtractionStatus.idle ||
        existing.aiRoleExtraction.status == ScriptAiRoleExtractionStatus.idle) {
      return draft;
    }
    return RecastScriptCache(
      scriptId: draft.scriptId,
      scriptName: draft.scriptName,
      sourceRootPath: draft.sourceRootPath,
      sourceFingerprint: draft.sourceFingerprint,
      sourceContentFingerprint: draft.sourceContentFingerprint,
      updatedAt: draft.updatedAt,
      roleCandidates: draft.roleCandidates,
      mapping: draft.mapping,
      aiRoleExtraction: existing.aiRoleExtraction,
      aiRoleExtractionChunks: existing.aiRoleExtractionChunks,
      aiRoleExtractionDraftCollapsed: existing.aiRoleExtractionDraftCollapsed,
      scriptBlockWords: draft.scriptBlockWords,
      knowledgeSnapshot: draft.knowledgeSnapshot,
      scriptSnapshot: draft.scriptSnapshot.isNotEmpty
          ? draft.scriptSnapshot
          : existing.scriptSnapshot,
    );
  }

  bool sameScriptPath(String left, String right) {
    final normalizedLeft = normalizeScriptPath(left);
    final normalizedRight = normalizeScriptPath(right);
    if (normalizedLeft.isEmpty || normalizedRight.isEmpty) {
      return false;
    }
    if (normalizedLeft == normalizedRight) {
      return true;
    }
    final resolvedLeft = _resolveScriptPath(left);
    final resolvedRight = _resolveScriptPath(right);
    return resolvedLeft.isNotEmpty &&
        resolvedRight.isNotEmpty &&
        resolvedLeft == resolvedRight;
  }

  String normalizeScriptPath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String scriptPathLeaf(String path) {
    final segments = path
        .trim()
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    return segments.isEmpty ? '' : segments.last;
  }

  String normalizeScriptName(String name) {
    return name.trim().toLowerCase();
  }

  String _resolveScriptPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      return normalizeScriptPath(Directory(trimmed).resolveSymbolicLinksSync());
    } catch (_) {
      try {
        return normalizeScriptPath(
          Directory(trimmed).absolute.resolveSymbolicLinksSync(),
        );
      } catch (_) {
        return '';
      }
    }
  }
}

String _stableContentHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
