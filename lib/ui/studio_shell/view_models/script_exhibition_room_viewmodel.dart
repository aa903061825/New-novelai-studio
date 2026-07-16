import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_exhibition_recast_summary.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/tokenizer_script.dart';
import 'package:novel_studio/data/studio/services/script_exhibition_image_organizer_service.dart';
import 'package:novel_studio/data/studio/services/workbench_metadata_import_service.dart';

typedef ScriptExhibitionScriptsLoader = Future<List<TokenizerScript>>
    Function();
typedef ScriptExhibitionRecastCachesLoader = Future<List<RecastScriptCache>>
    Function();
typedef ScriptExhibitionRecastScriptsLoader
    = Future<List<RecastExhibitionScript>> Function();
typedef ScriptExhibitionRecastScriptLoader = Future<RecastExhibitionScript?>
    Function(String scriptId);
typedef ScriptExhibitionSnapshotBuilder = Future<ScriptExhibitionSnapshot>
    Function({
  required List<RecastExhibitionScript> recastScripts,
  required List<TokenizerScript> scripts,
  required List<ProductionPlan> plans,
  required List<StudioGalleryRecord> records,
});
typedef ScriptExhibitionProductionPlansLoader = Future<List<ProductionPlan>>
    Function();
typedef ScriptExhibitionGalleryRecordsLoader = Future<List<StudioGalleryRecord>>
    Function();
typedef ScriptExhibitionProductionPlansSaver = Future<void> Function(
  List<ProductionPlan> plans,
);
typedef ScriptExhibitionGalleryRecordsSaver = Future<void> Function(
  List<StudioGalleryRecord> records,
);
typedef ScriptExhibitionDefaultGeneratedImageRoot = Future<String> Function();
typedef ScriptExhibitionImageGenerationParamsLoader
    = Future<Map<String, dynamic>> Function(String imagePath);
typedef ScriptExhibitionItemGenerationParamsLoader
    = Future<Map<String, dynamic>> Function(ScriptExhibitionItem item);
typedef ScriptExhibitionScriptDeleter = Future<void> Function(
  ScriptExhibitionScript script, {
  bool deleteLocalFiles,
});
typedef ScriptExhibitionItemDeleter = Future<void> Function(
  ScriptExhibitionItem item, {
  bool deleteLocalFiles,
});
typedef ScriptExhibitionScriptImporter = Future<void> Function();
typedef ScriptExhibitionScriptImageImporter = Future<void> Function(
  ScriptExhibitionScript script,
);
typedef ScriptExhibitionScriptRenamer = Future<void> Function(
  ScriptExhibitionScript script,
  String label,
);
typedef ScriptExhibitionScriptCategoryAssigner = Future<void> Function(
  ScriptExhibitionScript script,
  String categoryName,
);
typedef ScriptExhibitionScriptsCategoryAssigner = Future<void> Function(
  Iterable<ScriptExhibitionScript> scripts,
  String categoryName,
);
typedef ScriptExhibitionScriptCategoryRemover = Future<void> Function(
  ScriptExhibitionScript script,
  String categoryName,
);
typedef ScriptExhibitionUserCategoriesLoader
    = Future<List<ScriptExhibitionUserCategory>> Function();
typedef ScriptExhibitionCategoryAssignmentsLoader
    = Future<Map<String, List<String>>> Function();
typedef ScriptExhibitionCategoryCreator = Future<void> Function(
  String categoryName,
);
typedef ScriptExhibitionCategoryDeleter = Future<void> Function(
  String categoryName,
);
typedef ScriptExhibitionImageAttachmentRenamer = Future<void> Function(
  ScriptExhibitionItem item,
  String label,
);
typedef ScriptExhibitionVersionLabelRenamer = Future<void> Function(
  ScriptExhibitionScript script,
  ScriptExhibitionVersion version,
  String label,
);
typedef ScriptExhibitionVersionDeleter = Future<void> Function(
  ScriptExhibitionScript script,
  ScriptExhibitionVersion version, {
  bool deleteLocalFiles,
});
typedef ScriptExhibitionItemCoverSetter = Future<void> Function(
  ScriptExhibitionItem item,
);

Future<List<TokenizerScript>> _loadNoTokenizerScripts() async => const [];

Future<List<RecastScriptCache>> _loadNoRecastCaches() async => const [];

Future<List<ScriptExhibitionUserCategory>> _loadNoUserCategories() async =>
    const [];

Future<Map<String, List<String>>> _loadNoCategoryAssignments() async =>
    const {};

enum ScriptExhibitionItemSourceKind {
  original,
  attachment,
  generated,
  queued,
  failed,
  gallery,
}

enum ScriptExhibitionScriptStatus { active, archived, needsAction }

enum ScriptExhibitionScriptSort { recent, title, imageCount, needsAction }

enum ScriptExhibitionItemSort { frame, recent, oldest }

class ScriptExhibitionFocus {
  final String scriptId;
  final String scriptTitle;
  final String sourceFolder;
  final int? frameIndex;
  final String? sourceFileName;
  final String? sourcePath;
  final String? productionPlanId;
  final String? recastRunId;
  final String? taskId;
  final String? imagePath;

  const ScriptExhibitionFocus({
    required this.scriptId,
    required this.scriptTitle,
    required this.sourceFolder,
    this.frameIndex,
    this.sourceFileName,
    this.sourcePath,
    this.productionPlanId,
    this.recastRunId,
    this.taskId,
    this.imagePath,
  });

  bool get canOpenWorkbench => sourceFolder.trim().isNotEmpty;

  bool get canOpenSingleWorkbench =>
      (imagePath?.trim().isNotEmpty ?? false) ||
      (sourcePath?.trim().isNotEmpty ?? false);

  bool get canOpenProductionTask =>
      (productionPlanId?.trim().isNotEmpty ?? false) &&
      (taskId?.trim().isNotEmpty ?? false);
}

class ScriptExhibitionSnapshot {
  static const empty = ScriptExhibitionSnapshot(
    scripts: [],
    totalImageCount: 0,
    generatedImageCount: 0,
    needsActionCount: 0,
  );

  final List<ScriptExhibitionScript> scripts;
  final int totalImageCount;
  final int generatedImageCount;
  final int needsActionCount;

  const ScriptExhibitionSnapshot({
    required this.scripts,
    required this.totalImageCount,
    required this.generatedImageCount,
    required this.needsActionCount,
  });

  int get totalScriptCount => scripts.length;
}

class ScriptExhibitionCategory {
  final String id;
  final String title;
  final String description;
  final int count;
  final List<String> tags;

  const ScriptExhibitionCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.count,
    this.tags = const [],
  });
}

class ScriptExhibitionUserCategory {
  final String id;
  final String title;
  final String description;
  final List<String> tags;

  const ScriptExhibitionUserCategory({
    required this.id,
    required this.title,
    required this.description,
    this.tags = const [],
  });
}

class ScriptExhibitionDetailFilter {
  final String id;
  final String title;
  final int count;

  const ScriptExhibitionDetailFilter({
    required this.id,
    required this.title,
    required this.count,
  });
}

class ScriptExhibitionSourceFolderCleanupPreview {
  final String sourceFolder;
  final bool sourceFolderExists;
  final List<String> sourceImagePaths;
  final List<String> retainedImagePaths;
  final List<String> removableImagePaths;

  const ScriptExhibitionSourceFolderCleanupPreview({
    required this.sourceFolder,
    required this.sourceFolderExists,
    this.sourceImagePaths = const [],
    this.retainedImagePaths = const [],
    this.removableImagePaths = const [],
  });

  int get removableCount => removableImagePaths.length;

  bool get canClean => sourceFolderExists && removableImagePaths.isNotEmpty;
}

class ScriptExhibitionSourceFolderCleanupResult {
  final ScriptExhibitionSourceFolderCleanupPreview preview;
  final List<String> deletedImagePaths;
  final List<String> failedImagePaths;

  const ScriptExhibitionSourceFolderCleanupResult({
    required this.preview,
    this.deletedImagePaths = const [],
    this.failedImagePaths = const [],
  });

  int get deletedCount => deletedImagePaths.length;

  int get failedCount => failedImagePaths.length;
}

class ScriptExhibitionScript {
  final String scriptId;
  final String title;
  final String sourceFolder;
  final DateTime updatedAt;
  final List<ScriptExhibitionVersion> versions;
  final ScriptExhibitionScriptStatus status;
  final List<String> categoryNames;
  final String? coverItemId;
  final int originalCount;
  final int generatedImageCount;
  final int imageLikeItemCount;
  final bool hasImage;
  final ScriptExhibitionItem? coverItem;
  final int pendingCount;
  final ScriptExhibitionItem? firstNeedsActionItem;
  final bool summaryOnly;
  final String searchText;

  const ScriptExhibitionScript({
    required this.scriptId,
    required this.title,
    required this.sourceFolder,
    required this.updatedAt,
    required this.versions,
    required this.status,
    this.categoryNames = const [],
    this.coverItemId,
    required this.originalCount,
    required this.generatedImageCount,
    required this.imageLikeItemCount,
    required this.hasImage,
    required this.coverItem,
    required this.pendingCount,
    required this.firstNeedsActionItem,
    this.summaryOnly = false,
    this.searchText = '',
  });

  List<ScriptExhibitionItem> get items => [
        for (final version in versions) ...version.items,
      ];

  ScriptExhibitionVersion? versionContainingItem(String itemId) {
    for (final version in versions) {
      if (version.items.any((item) => item.id == itemId)) {
        return version;
      }
    }
    return null;
  }

  ScriptExhibitionFocus get focus => ScriptExhibitionFocus(
        scriptId: scriptId,
        scriptTitle: title,
        sourceFolder: sourceFolder,
      );

  ScriptExhibitionScript copyWith({
    List<String>? categoryNames,
  }) {
    final nextCategoryNames = categoryNames ?? this.categoryNames;
    return ScriptExhibitionScript(
      scriptId: scriptId,
      title: title,
      sourceFolder: sourceFolder,
      updatedAt: updatedAt,
      versions: versions,
      status: status,
      categoryNames: nextCategoryNames,
      coverItemId: coverItemId,
      originalCount: originalCount,
      generatedImageCount: generatedImageCount,
      imageLikeItemCount: imageLikeItemCount,
      hasImage: hasImage,
      coverItem: coverItem,
      pendingCount: pendingCount,
      firstNeedsActionItem: firstNeedsActionItem,
      summaryOnly: summaryOnly,
      searchText: categoryNames == null
          ? searchText
          : _scriptSearchTextFromValues(
              scriptId: scriptId,
              title: title,
              sourceFolder: sourceFolder,
              categoryNames: nextCategoryNames,
              versions: versions,
            ),
    );
  }
}

String _scriptSearchTextFromScript(ScriptExhibitionScript script) {
  return _scriptSearchTextFromValues(
    scriptId: script.scriptId,
    title: script.title,
    sourceFolder: script.sourceFolder,
    categoryNames: script.categoryNames,
    versions: script.versions,
  );
}

String _scriptSearchTextFromValues({
  required String scriptId,
  required String title,
  required String sourceFolder,
  required List<String> categoryNames,
  required List<ScriptExhibitionVersion> versions,
}) {
  final parts = <String>[
    scriptId,
    title,
    sourceFolder,
    ...categoryNames,
    for (final version in versions) ...[
      version.id,
      version.label,
      version.description,
      for (final item in version.items) ...[
        item.id,
        item.title,
        item.subtitle,
        item.sourceFileName ?? '',
        item.sourcePath ?? '',
        item.prompt,
        item.statusLabel,
      ],
    ],
  ];
  return parts.join('\n').toLowerCase();
}

class ScriptExhibitionVersion {
  static const originalId = 'original';
  static const galleryId = 'gallery';

  final String id;
  final String label;
  final String description;
  final DateTime updatedAt;
  final List<ScriptExhibitionItem> items;

  const ScriptExhibitionVersion({
    required this.id,
    required this.label,
    required this.description,
    required this.updatedAt,
    required this.items,
  });
}

class ScriptExhibitionItem {
  final String id;
  final String scriptId;
  final String scriptTitle;
  final String sourceFolder;
  final String versionId;
  final String versionLabel;
  final ScriptExhibitionItemSourceKind sourceKind;
  final int? frameIndex;
  final String? sourceFileName;
  final String? sourcePath;
  final String title;
  final String subtitle;
  final String prompt;
  final String imagePath;
  final String statusLabel;
  final DateTime updatedAt;
  final String? productionPlanId;
  final String? recastRunId;
  final String? taskId;
  final String? galleryRecordId;
  final StudioGalleryRecord? galleryRecord;
  final Map<String, dynamic>? assetCapturePayload;
  final Map<String, dynamic> generationParams;
  final String? imageAttachmentId;

  const ScriptExhibitionItem({
    required this.id,
    required this.scriptId,
    required this.scriptTitle,
    required this.sourceFolder,
    required this.versionId,
    required this.versionLabel,
    required this.sourceKind,
    required this.frameIndex,
    required this.sourceFileName,
    this.sourcePath,
    required this.title,
    required this.subtitle,
    required this.prompt,
    required this.imagePath,
    required this.statusLabel,
    required this.updatedAt,
    this.productionPlanId,
    this.recastRunId,
    this.taskId,
    this.galleryRecordId,
    this.galleryRecord,
    this.assetCapturePayload,
    this.generationParams = const {},
    this.imageAttachmentId,
  });

  ScriptExhibitionItem copyWith({
    String? versionLabel,
  }) {
    return ScriptExhibitionItem(
      id: id,
      scriptId: scriptId,
      scriptTitle: scriptTitle,
      sourceFolder: sourceFolder,
      versionId: versionId,
      versionLabel: versionLabel ?? this.versionLabel,
      sourceKind: sourceKind,
      frameIndex: frameIndex,
      sourceFileName: sourceFileName,
      sourcePath: sourcePath,
      title: title,
      subtitle: subtitle,
      prompt: prompt,
      imagePath: imagePath,
      statusLabel: statusLabel,
      updatedAt: updatedAt,
      productionPlanId: productionPlanId,
      recastRunId: recastRunId,
      taskId: taskId,
      galleryRecordId: galleryRecordId,
      galleryRecord: galleryRecord,
      assetCapturePayload: assetCapturePayload,
      generationParams: generationParams,
      imageAttachmentId: imageAttachmentId,
    );
  }

  bool get hasImage => imagePath.trim().isNotEmpty;

  bool get canDelete {
    if (sourceKind == ScriptExhibitionItemSourceKind.original) {
      return false;
    }
    if (imageAttachmentId != null && imageAttachmentId!.trim().isNotEmpty) {
      return true;
    }
    if (galleryRecordId != null && galleryRecordId!.trim().isNotEmpty) {
      return true;
    }
    return productionPlanId != null &&
        productionPlanId!.trim().isNotEmpty &&
        taskId != null &&
        taskId!.trim().isNotEmpty;
  }

  bool get canRename =>
      imageAttachmentId != null &&
      imageAttachmentId!.trim().isNotEmpty &&
      sourceKind == ScriptExhibitionItemSourceKind.attachment;

  bool get needsAction =>
      sourceKind == ScriptExhibitionItemSourceKind.failed ||
      sourceKind == ScriptExhibitionItemSourceKind.queued ||
      statusLabel.contains('待') ||
      statusLabel.contains('失败');

  ScriptExhibitionFocus get focus => ScriptExhibitionFocus(
        scriptId: scriptId,
        scriptTitle: scriptTitle,
        sourceFolder: sourceFolder,
        frameIndex: frameIndex,
        sourceFileName: sourceFileName,
        sourcePath: sourcePath,
        productionPlanId: productionPlanId,
        recastRunId: recastRunId,
        taskId: taskId,
        imagePath: imagePath.trim().isEmpty ? null : imagePath,
      );
}

class ScriptExhibitionRoomViewModel extends ChangeNotifier {
  static const allCategoryId = 'all';
  static const uncategorizedCategoryId = 'uncategorized';
  static const activeCategoryId = 'active';
  static const archivedCategoryId = 'archived';
  static const needsActionCategoryId = 'needs-action';
  static const allDetailFilterId = 'detail-all';
  static const completedDetailFilterId = 'detail-completed';
  static const needsActionDetailFilterId = 'detail-needs-action';

  final ScriptExhibitionScriptsLoader loadScripts;
  final ScriptExhibitionRecastCachesLoader loadRecastCaches;
  final ScriptExhibitionRecastScriptsLoader? loadRecastScripts;
  final ScriptExhibitionRecastScriptLoader? loadRecastScript;
  final ScriptExhibitionSnapshotBuilder _snapshotBuilder;
  final ScriptExhibitionProductionPlansLoader loadProductionPlans;
  final ScriptExhibitionGalleryRecordsLoader loadGalleryRecords;
  final ScriptExhibitionProductionPlansSaver? saveProductionPlans;
  final ScriptExhibitionGalleryRecordsSaver? saveGalleryRecords;
  final ScriptExhibitionDefaultGeneratedImageRoot? defaultGeneratedImageRoot;
  final ScriptExhibitionImageGenerationParamsLoader loadImageGenerationParams;
  final ScriptExhibitionScriptImporter? importScriptFolder;
  final ScriptExhibitionScriptImageImporter? importScriptImages;
  final ScriptExhibitionScriptDeleter? deleteScriptRecord;
  final ScriptExhibitionItemDeleter? deleteItemRecord;
  final ScriptExhibitionScriptRenamer? renameScriptRecord;
  final ScriptExhibitionScriptCategoryAssigner? assignScriptCategory;
  final ScriptExhibitionScriptsCategoryAssigner? assignScriptsCategory;
  final ScriptExhibitionScriptCategoryRemover? removeScriptCategory;
  final ScriptExhibitionUserCategoriesLoader loadCustomCategories;
  final ScriptExhibitionCategoryAssignmentsLoader loadCustomCategoryScriptIds;
  final ScriptExhibitionCategoryCreator? createCategoryRecord;
  final ScriptExhibitionCategoryDeleter? deleteCategoryRecord;
  final ScriptExhibitionImageAttachmentRenamer? renameImageAttachment;
  final ScriptExhibitionVersionLabelRenamer? renameVersionLabelRecord;
  final ScriptExhibitionVersionDeleter? deleteVersionRecord;
  final ScriptExhibitionItemCoverSetter? setCoverItemRecord;
  final List<ScriptExhibitionUserCategory> customCategories;
  final Map<String, List<String>> customCategoryScriptIds;
  final List<ScriptExhibitionUserCategory> _sessionCategories = [];
  List<ScriptExhibitionUserCategory> _loadedCustomCategories = const [];
  Map<String, List<String>> _loadedCustomCategoryScriptIds = const {};
  final Set<String> _selectedScriptIds = {};
  final Set<String> _selectedVersionIds = {};

  ScriptExhibitionSnapshot _snapshot = ScriptExhibitionSnapshot.empty;
  bool isLoading = false;
  Object? loadError;
  String selectedCategoryId = allCategoryId;
  String? selectedScriptId;
  String? selectedVersionId;
  String selectedDetailFilterId = allDetailFilterId;
  String scriptSearchQuery = '';
  ScriptExhibitionScriptSort scriptSort = ScriptExhibitionScriptSort.recent;
  ScriptExhibitionItemSort itemSort = ScriptExhibitionItemSort.frame;
  String? focusedItemId;
  int _loadGeneration = 0;
  int _snapshotBuildRevision = 0;
  bool _hasLoaded = false;
  List<RecastExhibitionScript> _loadedRecastScripts = const [];
  List<TokenizerScript> _loadedScripts = const [];
  List<ProductionPlan> _loadedProductionPlans = const [];
  List<StudioGalleryRecord> _loadedGalleryRecords = const [];
  Map<String, ScriptExhibitionScript> _scriptsById = const {};
  Map<String, ScriptExhibitionItem> _itemsById = const {};
  Map<String, List<ScriptExhibitionScript>> _scriptsByCategoryName = const {};
  List<ScriptExhibitionScript> _uncategorizedScripts = const [];
  List<ScriptExhibitionScript> _activeScripts = const [];
  List<ScriptExhibitionScript> _archivedScripts = const [];
  List<ScriptExhibitionScript> _needsActionScripts = const [];
  List<ScriptExhibitionCategory>? _categoriesCache;
  final Set<({int generation, String scriptId})> _loadingScriptDetails = {};
  final Map<String, Future<Map<String, dynamic>>> _imageGenerationParamsCache =
      {};

  ScriptExhibitionRoomViewModel({
    ScriptExhibitionScriptsLoader? loadScripts,
    ScriptExhibitionRecastCachesLoader? loadRecastCaches,
    this.loadRecastScripts,
    this.loadRecastScript,
    @visibleForTesting ScriptExhibitionSnapshotBuilder? snapshotBuilder,
    required this.loadProductionPlans,
    required this.loadGalleryRecords,
    this.saveProductionPlans,
    this.saveGalleryRecords,
    this.defaultGeneratedImageRoot,
    ScriptExhibitionImageGenerationParamsLoader? loadImageGenerationParams,
    this.importScriptFolder,
    this.importScriptImages,
    this.deleteScriptRecord,
    this.deleteItemRecord,
    this.renameScriptRecord,
    this.assignScriptCategory,
    this.assignScriptsCategory,
    this.removeScriptCategory,
    ScriptExhibitionUserCategoriesLoader? loadCustomCategories,
    ScriptExhibitionCategoryAssignmentsLoader? loadCustomCategoryScriptIds,
    this.createCategoryRecord,
    this.deleteCategoryRecord,
    this.renameImageAttachment,
    ScriptExhibitionVersionLabelRenamer? renameVersionLabel,
    this.deleteVersionRecord,
    this.setCoverItemRecord,
    this.customCategories = const [],
    this.customCategoryScriptIds = const {},
  })  : _snapshotBuilder = snapshotBuilder ?? _buildSnapshotAsync,
        loadScripts = loadScripts ?? _loadNoTokenizerScripts,
        loadRecastCaches = loadRecastCaches ?? _loadNoRecastCaches,
        loadCustomCategories = loadCustomCategories ?? _loadNoUserCategories,
        loadCustomCategoryScriptIds =
            loadCustomCategoryScriptIds ?? _loadNoCategoryAssignments,
        loadImageGenerationParams =
            loadImageGenerationParams ?? _loadImageGenerationParamsFromMetadata,
        renameVersionLabelRecord = renameVersionLabel;

  bool get canImportScripts => importScriptFolder != null;

  bool get canImportScriptImages => importScriptImages != null;

  bool get canDeleteScripts => deleteScriptRecord != null;

  bool get canDeleteItems => deleteItemRecord != null;

  bool get canRenameScripts => renameScriptRecord != null;

  bool get canCategorizeScripts =>
      assignScriptCategory != null || assignScriptsCategory != null;

  bool get canRemoveScriptCategories => removeScriptCategory != null;

  bool get canDeleteCategories => deleteCategoryRecord != null;

  Set<String> get selectedScriptIds => Set.unmodifiable(_selectedScriptIds);

  Set<String> get selectedVersionIds => Set.unmodifiable(_selectedVersionIds);

  List<ScriptExhibitionVersion> get selectedVersions {
    final script = selectedScript;
    if (script == null || _selectedVersionIds.isEmpty) {
      return const [];
    }
    return [
      for (final version in script.versions)
        if (_selectedVersionIds.contains(version.id) &&
            canDeleteVersion(script, version))
          version,
    ];
  }

  bool get canRenameItems => renameImageAttachment != null;

  bool get canRenameVersions => renameVersionLabelRecord != null;

  bool get canDeleteVersions => deleteVersionRecord != null;

  bool get canSetCoverItems => setCoverItemRecord != null;

  ScriptExhibitionSnapshot get snapshot => _snapshot;

  set snapshot(ScriptExhibitionSnapshot value) {
    _setSnapshot(value);
  }

  List<ScriptExhibitionCategory> get categories =>
      _categoriesCache ??= _buildCategories();

  Map<String, List<String>> get _effectiveCustomCategoryScriptIds {
    if (customCategoryScriptIds.isEmpty &&
        _loadedCustomCategoryScriptIds.isEmpty) {
      return const {};
    }
    final merged = <String, Set<String>>{};
    void merge(Map<String, List<String>> source) {
      for (final entry in source.entries) {
        final id = entry.key.trim();
        if (id.isEmpty) continue;
        final bucket = merged.putIfAbsent(id, () => <String>{});
        for (final scriptId in entry.value) {
          final normalized = scriptId.trim();
          if (normalized.isNotEmpty) {
            bucket.add(normalized);
          }
        }
      }
    }

    merge(customCategoryScriptIds);
    merge(_loadedCustomCategoryScriptIds);
    return Map.unmodifiable({
      for (final entry in merged.entries)
        if (entry.value.isNotEmpty)
          entry.key: List<String>.unmodifiable(entry.value),
    });
  }

  List<ScriptExhibitionCategory> _buildCategories() {
    return List<ScriptExhibitionCategory>.unmodifiable([
      ScriptExhibitionCategory(
        id: allCategoryId,
        title: '全部馆区',
        description: '所有剧本、原始帧和批量结果统一浏览。',
        count: snapshot.totalScriptCount,
        tags: const ['剧本', '原图', '新图'],
      ),
      ScriptExhibitionCategory(
        id: uncategorizedCategoryId,
        title: '未分类',
        description: '还没有归入自定义分类的脚本。',
        count: _uncategorizedScripts.length,
        tags: const ['默认分类'],
      ),
      for (final category in _registeredCustomCategories())
        ScriptExhibitionCategory(
          id: category.id,
          title: category.title,
          description: category.description,
          count: _scriptsForCustomCategory(category.id).length,
          tags: category.tags,
        ),
      for (final category in _derivedCustomCategories())
        ScriptExhibitionCategory(
          id: category.id,
          title: category.title,
          description: category.description,
          count: _scriptsForCustomCategory(category.id).length,
          tags: category.tags,
        ),
    ]);
  }

  List<ScriptExhibitionScript> get visibleScripts {
    List<ScriptExhibitionScript> scripts;
    if (selectedCategoryId != allCategoryId) {
      final categoryName = _customCategoryNameFromId(selectedCategoryId);
      if (categoryName != null) {
        scripts = _scriptsForCustomCategory(selectedCategoryId);
        return _sortVisibleScripts(_filterScriptsBySearchQuery(scripts));
      }
      final assignedIds = _effectiveCustomCategoryScriptIds[selectedCategoryId];
      if (assignedIds != null) {
        scripts = _scriptsForAssignedIds(assignedIds);
        return _sortVisibleScripts(_filterScriptsBySearchQuery(scripts));
      }
    }
    scripts = switch (selectedCategoryId) {
      allCategoryId => snapshot.scripts,
      uncategorizedCategoryId => _uncategorizedScripts,
      activeCategoryId => _activeScripts,
      archivedCategoryId => _archivedScripts,
      needsActionCategoryId => _needsActionScripts,
      _ => snapshot.scripts,
    };
    return _sortVisibleScripts(_filterScriptsBySearchQuery(scripts));
  }

  ScriptExhibitionItem? get focusedItem {
    final itemId = focusedItemId;
    if (itemId == null) return null;
    return _itemsById[itemId];
  }

  ScriptExhibitionScript? get selectedScript {
    final id = selectedScriptId;
    if (id == null) return null;
    return _scriptsById[id];
  }

  bool get isSelectedScriptDetailLoading {
    final scriptId = selectedScriptId;
    if (scriptId == null) return false;
    return _loadingScriptDetails.contains((
      generation: _loadGeneration,
      scriptId: scriptId,
    ));
  }

  ScriptExhibitionVersion? get selectedVersion {
    final script = selectedScript;
    if (script == null || script.versions.isEmpty) return null;
    final id = selectedVersionId;
    if (id == null) return script.versions.first;
    return script.versions.where((version) => version.id == id).firstOrNull ??
        script.versions.first;
  }

  List<ScriptExhibitionDetailFilter> get detailFilters {
    final items = selectedVersion?.items ?? const <ScriptExhibitionItem>[];
    final needsActionCount = items.where((item) => item.needsAction).length;
    return [
      ScriptExhibitionDetailFilter(
        id: allDetailFilterId,
        title: '全部',
        count: items.length,
      ),
      ScriptExhibitionDetailFilter(
        id: completedDetailFilterId,
        title: '已完成',
        count: items.length - needsActionCount,
      ),
      ScriptExhibitionDetailFilter(
        id: needsActionDetailFilterId,
        title: '需处理',
        count: needsActionCount,
      ),
    ];
  }

  List<ScriptExhibitionItem> get visibleVersionItems {
    final items = selectedVersion?.items ?? const <ScriptExhibitionItem>[];
    final filtered = switch (selectedDetailFilterId) {
      allDetailFilterId => items,
      completedDetailFilterId =>
        items.where((item) => !item.needsAction).toList(growable: false),
      needsActionDetailFilterId =>
        items.where((item) => item.needsAction).toList(growable: false),
      _ => items,
    };
    return _sortVisibleItems(filtered);
  }

  Future<ScriptExhibitionSourceFolderCleanupPreview> previewSourceFolderCleanup(
    ScriptExhibitionScript script,
  ) async {
    final currentScript = await _scriptForSourceFolderCleanup(script);
    return _previewSourceFolderCleanup(currentScript);
  }

  Future<ScriptExhibitionImageOrganizationPreview>
      previewScriptImageOrganization(
    ScriptExhibitionScript script,
  ) async {
    final plans = await loadProductionPlans();
    final records = await loadGalleryRecords();
    final organizationScripts = _scriptsForImageOrganization(script);
    final targetScriptTitlesById = _scriptTitlesByIdForOrganization(
      organizationScripts,
    );
    final defaultOutputRoot = await _defaultOutputRootForOrganization(
      plans,
      targetScriptIds: targetScriptTitlesById.keys.toSet(),
    );
    final generatedRoots = await _generatedRootsForOrganization(plans);
    final service = ScriptExhibitionImageOrganizerService(
      defaultOutputRoot: () async => defaultOutputRoot,
    );
    return service.preview(
      targetScriptTitlesById: targetScriptTitlesById,
      productionPlans: plans,
      galleryRecords: records,
      generatedRoots: generatedRoots,
      originalSourcePaths: _originalSourceImagePathsForScripts(
        organizationScripts,
      ),
    );
  }

  Future<ScriptExhibitionImageOrganizationResult> organizeScriptImages(
    ScriptExhibitionScript script, {
    ScriptExhibitionImageOrganizationPreview? preview,
  }) async {
    final plansSaver = saveProductionPlans;
    final recordsSaver = saveGalleryRecords;
    if (plansSaver == null || recordsSaver == null) {
      throw StateError(
        'Script image organization requires production plan and gallery '
        'record savers before moving or deleting files.',
      );
    }
    final previousScriptId = selectedScriptId;
    final previousVersionId = selectedVersionId;
    final currentPreview =
        preview ?? await previewScriptImageOrganization(script);
    final defaultOutputRoot = await _defaultOutputRootForOrganization(
      currentPreview.productionPlans,
      targetScriptIds:
          _scriptTitlesByIdForOrganization(_scriptsForImageOrganization(script))
              .keys
              .toSet(),
    );
    final service = ScriptExhibitionImageOrganizerService(
      defaultOutputRoot: () async => defaultOutputRoot,
    );
    final result = await service.apply(currentPreview);
    if (result.failedImagePaths.isEmpty) {
      // The filesystem and JSON stores are not transactional here, but both
      // stores receive updates from the same successful apply result. If either
      // save throws, the caller sees the persistence error.
      await plansSaver(result.updatedProductionPlans);
      await recordsSaver(result.updatedGalleryRecords);
      await load();
      _restoreSelectionIfPresent(
        scriptId: previousScriptId,
        versionId: previousVersionId,
      );
    }
    return result;
  }

  Future<String> _defaultOutputRootForOrganization(
    List<ProductionPlan> plans, {
    required Set<String> targetScriptIds,
  }) async {
    final injectedRoot = await _resolvedInjectedDefaultGeneratedRoot();
    if (injectedRoot != null) {
      return injectedRoot;
    }
    if (_organizationNeedsDefaultGeneratedRoot(
      plans,
      targetScriptIds: targetScriptIds,
    )) {
      throw StateError(
        'Script image organization requires defaultGeneratedImageRoot when a '
        'matching production task has no output directory.',
      );
    }
    final planRoot = _firstPlanOutputRoot(plans);
    if (planRoot != null) {
      return planRoot;
    }
    throw StateError(
      'Script image organization requires defaultGeneratedImageRoot or at '
      'least one production plan output directory.',
    );
  }

  Future<String?> _resolvedInjectedDefaultGeneratedRoot() async {
    final resolver = defaultGeneratedImageRoot;
    if (resolver == null) {
      return null;
    }
    final root = (await resolver()).trim();
    if (root.isEmpty) {
      return null;
    }
    return Directory(root).absolute.path;
  }

  bool _organizationNeedsDefaultGeneratedRoot(
    List<ProductionPlan> plans, {
    required Set<String> targetScriptIds,
  }) {
    for (final plan in plans) {
      final planRoot = plan.executionSettings?.outputDirectory.trim();
      if (planRoot != null && planRoot.isNotEmpty) {
        continue;
      }
      for (final task in plan.tasks) {
        final outputImagePath = task.outputImagePath?.trim();
        if (task.taskType == ProductionTaskType.scriptRecastFrame &&
            task.status == ProductionTaskStatus.completed &&
            targetScriptIds.contains(task.source.scriptId?.trim()) &&
            outputImagePath != null &&
            outputImagePath.isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  String? _firstPlanOutputRoot(List<ProductionPlan> plans) {
    for (final plan in plans) {
      final root = plan.executionSettings?.outputDirectory.trim();
      if (root != null && root.isNotEmpty) {
        return Directory(root).absolute.path;
      }
    }
    return null;
  }

  Future<List<String>> _generatedRootsForOrganization(
    List<ProductionPlan> plans,
  ) async {
    final rootsByKey = <String, String>{};
    void add(String? path) {
      final trimmed = path?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        return;
      }
      rootsByKey.putIfAbsent(
        _normalizedDirectoryPathKey(trimmed),
        () => Directory(trimmed).absolute.path,
      );
    }

    for (final plan in plans) {
      add(plan.executionSettings?.outputDirectory);
    }
    add(await _resolvedInjectedDefaultGeneratedRoot());
    return List.unmodifiable(rootsByKey.values);
  }

  List<ScriptExhibitionScript> _scriptsForImageOrganization(
    ScriptExhibitionScript triggerScript,
  ) {
    final scriptsById = <String, ScriptExhibitionScript>{};
    for (final script in snapshot.scripts) {
      if (script.scriptId.trim().isNotEmpty) {
        scriptsById[script.scriptId.trim()] = script;
      }
    }
    if (triggerScript.scriptId.trim().isNotEmpty) {
      scriptsById.putIfAbsent(
        triggerScript.scriptId.trim(),
        () => triggerScript,
      );
    }
    return List.unmodifiable(scriptsById.values);
  }

  Map<String, String> _scriptTitlesByIdForOrganization(
    Iterable<ScriptExhibitionScript> scripts,
  ) {
    return Map.unmodifiable({
      for (final script in scripts)
        if (script.scriptId.trim().isNotEmpty)
          script.scriptId.trim(): script.title.trim(),
    });
  }

  Set<String> _originalSourceImagePathsForScripts(
    Iterable<ScriptExhibitionScript> scripts,
  ) {
    final pathsByKey = <String, String>{};
    for (final script in scripts) {
      for (final item in script.items) {
        final sourcePath = item.sourcePath?.trim();
        if (sourcePath != null &&
            sourcePath.isNotEmpty &&
            _isLocalImageReference(sourcePath)) {
          pathsByKey.putIfAbsent(
            _normalizedFilePathKey(sourcePath),
            () => File(sourcePath).absolute.path,
          );
        }
        final imagePath = item.imagePath.trim();
        if (item.sourceKind == ScriptExhibitionItemSourceKind.original &&
            imagePath.isNotEmpty &&
            _isLocalImageReference(imagePath)) {
          pathsByKey.putIfAbsent(
            _normalizedFilePathKey(imagePath),
            () => File(imagePath).absolute.path,
          );
        }
      }
    }
    return Set.unmodifiable(pathsByKey.values);
  }

  Future<ScriptExhibitionSourceFolderCleanupResult> cleanSourceFolderImages(
    ScriptExhibitionScript script, {
    ScriptExhibitionSourceFolderCleanupPreview? preview,
  }) async {
    final cleanupPreview = preview ?? await previewSourceFolderCleanup(script);
    final deleted = <String>[];
    final failed = <String>[];
    for (final path in cleanupPreview.removableImagePaths) {
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type != FileSystemEntityType.file) {
          continue;
        }
        await File(path).delete();
        deleted.add(path);
      } on FileSystemException {
        failed.add(path);
      }
    }
    return ScriptExhibitionSourceFolderCleanupResult(
      preview: cleanupPreview,
      deletedImagePaths: List.unmodifiable(deleted),
      failedImagePaths: List.unmodifiable(failed),
    );
  }

  Future<ScriptExhibitionScript> _scriptForSourceFolderCleanup(
    ScriptExhibitionScript script,
  ) async {
    if (script.summaryOnly) {
      await _loadScriptDetailIfNeeded(script.scriptId);
    }
    return _scriptMatching(script) ?? script;
  }

  List<ScriptExhibitionScript> get selectedShelfScripts {
    if (_selectedScriptIds.isEmpty) return const [];
    final selectedIds = _selectedScriptIds.toSet();
    return snapshot.scripts
        .where((script) => selectedIds.contains(script.scriptId))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> loadGenerationParamsForItem(
    ScriptExhibitionItem item,
  ) {
    final existing = _knownGenerationParamsForItem(item);
    if (_hasDisplayedGenerationParams(existing)) {
      return Future.value(existing);
    }
    final imagePath = item.imagePath.trim();
    if (!_isLocalImagePath(imagePath)) {
      return Future.value(existing);
    }
    final loaded = _imageGenerationParamsCache.putIfAbsent(imagePath, () async {
      final params = await loadImageGenerationParams(imagePath);
      return _lightweightProductionParameters(params);
    });
    return loaded.then((params) {
      if (existing.isEmpty) {
        return params;
      }
      return Map<String, dynamic>.unmodifiable({
        ...existing,
        ...params,
      });
    });
  }

  List<ScriptExhibitionScript> _sortVisibleScripts(
    List<ScriptExhibitionScript> scripts,
  ) {
    if (scriptSort == ScriptExhibitionScriptSort.recent) {
      return scripts;
    }
    return [...scripts]
      ..sort((left, right) => _compareScriptsForSort(left, right, scriptSort));
  }

  List<ScriptExhibitionScript> _filterScriptsBySearchQuery(
    List<ScriptExhibitionScript> scripts,
  ) {
    final terms = scriptSearchQuery
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return scripts;
    return scripts.where((script) {
      final searchText = script.searchText.isNotEmpty
          ? script.searchText
          : _scriptSearchTextFromScript(script);
      return terms.every(searchText.contains);
    }).toList(growable: false);
  }

  List<ScriptExhibitionItem> _sortVisibleItems(
    Iterable<ScriptExhibitionItem> items,
  ) {
    if (itemSort == ScriptExhibitionItemSort.frame) {
      return items is List<ScriptExhibitionItem>
          ? items
          : items.toList(growable: false);
    }
    final sorted = items.toList(growable: false)
      ..sort((left, right) => _compareItemsForSort(left, right, itemSort));
    return sorted;
  }

  Future<void> ensureLoaded() async {
    if (_hasLoaded || isLoading) return;
    await load();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    var publishedBaseSnapshot = false;
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      final baseResults = await Future.wait<Object>([
        _loadRecastExhibitionScripts(),
        loadScripts(),
        loadCustomCategories(),
        loadCustomCategoryScriptIds(),
      ]);
      final recastScripts = baseResults[0] as List<RecastExhibitionScript>;
      final scripts = baseResults[1] as List<TokenizerScript>;
      final loadedCustomCategories =
          baseResults[2] as List<ScriptExhibitionUserCategory>;
      final loadedCustomCategoryScriptIds =
          baseResults[3] as Map<String, List<String>>;
      if (generation != _loadGeneration) {
        return;
      }
      _loadedRecastScripts = recastScripts;
      _loadedScripts = scripts;
      _loadedCustomCategories = loadedCustomCategories;
      _loadedCustomCategoryScriptIds = loadedCustomCategoryScriptIds;
      _loadedProductionPlans = const [];
      _loadedGalleryRecords = const [];
      final baseBuild = await _buildSnapshotForPublication(
        recastScripts: recastScripts,
        scripts: scripts,
        plans: const [],
        records: const [],
      );
      if (!_canPublishSnapshotBuild(
        generation: generation,
        revision: baseBuild.revision,
      )) {
        return;
      }
      _hasLoaded = true;
      isLoading = false;
      publishedBaseSnapshot = true;
      _publishSnapshot(baseBuild.snapshot);

      final galleryRecords = () async {
        try {
          return await loadGalleryRecords();
        } catch (_) {
          return const <StudioGalleryRecord>[];
        }
      }();
      final results = await Future.wait<Object>([
        loadProductionPlans(),
        galleryRecords,
      ]).catchError(
          (_) => const <Object>[<ProductionPlan>[], <StudioGalleryRecord>[]]);
      final plans = results[0] as List<ProductionPlan>;
      final records = results[1] as List<StudioGalleryRecord>;
      if (generation != _loadGeneration) {
        return;
      }
      _loadedProductionPlans = plans;
      _loadedGalleryRecords = records;
      final fullBuild = await _buildSnapshotForPublication(
        recastScripts: _loadedRecastScripts,
        scripts: _loadedScripts,
        plans: plans,
        records: records,
      );
      if (!_canPublishSnapshotBuild(
        generation: generation,
        revision: fullBuild.revision,
      )) {
        return;
      }
      _publishSnapshot(fullBuild.snapshot);
    } catch (error) {
      if (generation != _loadGeneration) {
        return;
      }
      loadError = error;
    } finally {
      if (generation == _loadGeneration && !publishedBaseSnapshot) {
        _hasLoaded = true;
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<RecastExhibitionScript>> _loadRecastExhibitionScripts() async {
    final loader = loadRecastScripts;
    if (loader != null) {
      return loader();
    }
    final caches = await loadRecastCaches();
    return [
      for (final cache in caches)
        if (RecastExhibitionScript.tryFromCache(cache) case final script?)
          script,
    ];
  }

  Future<void> importScript() async {
    final importer = importScriptFolder;
    if (importer == null) return;
    await importer();
    await load();
  }

  Future<void> importImagesForScript(ScriptExhibitionScript script) async {
    final importer = importScriptImages;
    if (importer == null) return;
    final previousAttachmentIds = _attachmentIdsForScript(script);
    await importer(script);
    await load();
    final refreshedScript = _scriptMatching(script);
    final focusedAttachment = refreshedScript?.items.firstWhere(
      (item) {
        final attachmentId = item.imageAttachmentId?.trim();
        return item.sourceKind == ScriptExhibitionItemSourceKind.attachment &&
            attachmentId != null &&
            attachmentId.isNotEmpty &&
            !previousAttachmentIds.contains(attachmentId);
      },
      orElse: () => refreshedScript.items.firstWhere(
        (item) => item.sourceKind == ScriptExhibitionItemSourceKind.attachment,
        orElse: () => refreshedScript.items.first,
      ),
    );
    if (refreshedScript == null || focusedAttachment == null) {
      return;
    }
    selectedScriptId = refreshedScript.scriptId;
    selectedVersionId =
        refreshedScript.versionContainingItem(focusedAttachment.id)?.id;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = focusedAttachment.id;
    _selectedVersionIds.clear();
    notifyListeners();
  }

  Set<String> _attachmentIdsForScript(ScriptExhibitionScript script) {
    return {
      for (final item in script.items)
        if (item.sourceKind == ScriptExhibitionItemSourceKind.attachment)
          if (item.imageAttachmentId?.trim() case final id?)
            if (id.isNotEmpty) id,
    };
  }

  ScriptExhibitionScript? _scriptMatching(ScriptExhibitionScript target) {
    final targetAliases = _scriptStrongAliases(
      scriptId: target.scriptId,
      sourceFolder: target.sourceFolder,
    ).toSet();
    if (targetAliases.isNotEmpty) {
      for (final script in snapshot.scripts) {
        final scriptAliases = _scriptStrongAliases(
          scriptId: script.scriptId,
          sourceFolder: script.sourceFolder,
        ).toSet();
        if (targetAliases.intersection(scriptAliases).isNotEmpty) {
          return script;
        }
      }
    }

    final titleAlias = _scriptTitleAlias(target.title);
    if (titleAlias == null) return null;
    for (final script in snapshot.scripts) {
      if (_scriptTitleAlias(script.title) == titleAlias) {
        return script;
      }
    }
    return null;
  }

  void selectCategory(String categoryId) {
    if (selectedCategoryId == categoryId) return;
    selectedCategoryId = categoryId;
    selectedScriptId = null;
    selectedVersionId = null;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    _selectedScriptIds.clear();
    _selectedVersionIds.clear();
    notifyListeners();
  }

  void selectScript(String scriptId) {
    selectedScriptId = scriptId;
    selectedVersionId = selectedScript?.versions.firstOrNull?.id;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    _selectedScriptIds.clear();
    _selectedVersionIds.clear();
    notifyListeners();
    unawaited(_loadScriptDetailIfNeeded(scriptId));
  }

  Future<void> _loadScriptDetailIfNeeded(String scriptId) async {
    final loader = loadRecastScript;
    if (loader == null) return;
    final generation = _loadGeneration;
    final current = _scriptsById[scriptId];
    if (current == null || !current.summaryOnly) return;
    final requestKey = (generation: generation, scriptId: scriptId);
    if (!_loadingScriptDetails.add(requestKey)) return;
    notifyListeners();
    try {
      final detail = await loader(scriptId);
      if (detail == null || generation == 0 || generation != _loadGeneration) {
        return;
      }
      final nextRecastScripts = [
        for (final script in _loadedRecastScripts)
          script.scriptId == scriptId ? detail : script,
      ];
      if (generation != _loadGeneration) return;
      _loadedRecastScripts = nextRecastScripts;
      final detailBuild = await _buildSnapshotForPublication(
        recastScripts: nextRecastScripts,
        scripts: _loadedScripts,
        plans: _loadedProductionPlans,
        records: _loadedGalleryRecords,
      );
      if (!_canPublishSnapshotBuild(
        generation: generation,
        revision: detailBuild.revision,
      )) {
        return;
      }
      _publishSnapshot(detailBuild.snapshot);
    } catch (error, stackTrace) {
      if (generation == _loadGeneration) {
        debugPrint(
            'Script exhibition detail load failed for $scriptId: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      _loadingScriptDetails.remove(requestKey);
      if (generation == _loadGeneration && selectedScriptId == scriptId) {
        notifyListeners();
      }
    }
  }

  void retrySelectedScriptDetail() {
    final script = selectedScript;
    if (script == null || !script.summaryOnly) return;
    unawaited(_loadScriptDetailIfNeeded(script.scriptId));
  }

  void clearScriptSelection() {
    selectedScriptId = null;
    selectedVersionId = null;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    _selectedScriptIds.clear();
    _selectedVersionIds.clear();
    notifyListeners();
  }

  void replaceShelfSelection(Iterable<String> scriptIds) {
    final visibleIds = visibleScripts.map((script) => script.scriptId).toSet();
    final next = {
      for (final scriptId in scriptIds)
        if (visibleIds.contains(scriptId)) scriptId,
    };
    if (setEquals(_selectedScriptIds, next)) return;
    _selectedScriptIds
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void toggleShelfSelection(String scriptId) {
    if (!visibleScripts.any((script) => script.scriptId == scriptId)) return;
    if (_selectedScriptIds.contains(scriptId)) {
      _selectedScriptIds.remove(scriptId);
    } else {
      _selectedScriptIds.add(scriptId);
    }
    notifyListeners();
  }

  void clearShelfSelection() {
    if (_selectedScriptIds.isEmpty) return;
    _selectedScriptIds.clear();
    notifyListeners();
  }

  void updateScriptSearchQuery(String value) {
    if (scriptSearchQuery == value) return;
    scriptSearchQuery = value;
    _normalizeShelfSelectionForVisibleScripts();
    notifyListeners();
  }

  void clearScriptSearchQuery() {
    updateScriptSearchQuery('');
  }

  void selectVersion(String versionId) {
    selectedVersionId = versionId;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    notifyListeners();
  }

  void toggleVersionSelection(String versionId) {
    final script = selectedScript;
    if (script == null) return;
    final version = script.versions
        .where((candidate) => candidate.id == versionId)
        .firstOrNull;
    if (version == null || !canDeleteVersion(script, version)) {
      return;
    }
    if (_selectedVersionIds.contains(version.id)) {
      _selectedVersionIds.remove(version.id);
    } else {
      _selectedVersionIds.add(version.id);
    }
    notifyListeners();
  }

  void clearVersionSelection() {
    if (_selectedVersionIds.isEmpty) return;
    _selectedVersionIds.clear();
    notifyListeners();
  }

  void selectDetailFilter(String filterId) {
    if (selectedDetailFilterId == filterId) return;
    selectedDetailFilterId = filterId;
    focusedItemId = null;
    notifyListeners();
  }

  void selectScriptSort(ScriptExhibitionScriptSort sort) {
    if (scriptSort == sort) return;
    scriptSort = sort;
    _selectedScriptIds.clear();
    notifyListeners();
  }

  void selectItemSort(ScriptExhibitionItemSort sort) {
    if (itemSort == sort) return;
    itemSort = sort;
    focusedItemId = null;
    notifyListeners();
  }

  void jumpToFirstNeedsAction() {
    for (final script in snapshot.scripts) {
      final item = script.firstNeedsActionItem;
      if (item == null) continue;
      selectedCategoryId = allCategoryId;
      selectedScriptId = script.scriptId;
      selectedVersionId = script.versionContainingItem(item.id)?.id ??
          script.versions.firstOrNull?.id;
      selectedDetailFilterId = needsActionDetailFilterId;
      focusedItemId = item.id;
      _selectedVersionIds.clear();
      notifyListeners();
      return;
    }
  }

  Future<void> deleteScript(
    ScriptExhibitionScript script, {
    bool deleteLocalFiles = false,
  }) async {
    final deleter = deleteScriptRecord;
    if (deleter == null) return;
    await deleter(script, deleteLocalFiles: deleteLocalFiles);
    if (selectedScriptId == script.scriptId) {
      selectedScriptId = null;
      selectedVersionId = null;
      _selectedVersionIds.clear();
    }
    await load();
  }

  Future<void> deleteItem(
    ScriptExhibitionItem item, {
    bool deleteLocalFiles = false,
  }) async {
    final deleter = deleteItemRecord;
    if (deleter == null || !item.canDelete) return;
    await deleter(item, deleteLocalFiles: deleteLocalFiles);
    if (_itemDeleteTouchesRecast(item)) {
      await load();
      return;
    }
    if (await _refreshAfterItemDelete(item)) {
      return;
    }
    final snapshotChanged = _removeItemFromCurrentSnapshot(item);
    if (snapshotChanged) {
      notifyListeners();
    }
  }

  bool canDeleteVersion(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
  ) {
    if (deleteVersionRecord == null) return false;
    if (version.id == ScriptExhibitionVersion.originalId) return false;
    if (!script.versions.any((candidate) => candidate.id == version.id)) {
      return false;
    }
    return version.items.any((item) => item.canDelete);
  }

  Future<void> deleteVersion(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version, {
    bool deleteLocalFiles = false,
  }) async {
    await deleteVersions(
      script,
      [version],
      deleteLocalFiles: deleteLocalFiles,
    );
  }

  Future<void> deleteVersions(
    ScriptExhibitionScript script,
    Iterable<ScriptExhibitionVersion> versions, {
    bool deleteLocalFiles = false,
  }) async {
    final deleter = deleteVersionRecord;
    if (deleter == null) return;
    final currentScript = _scriptsById[script.scriptId] ?? script;
    final targetVersionsById = <String, ScriptExhibitionVersion>{};
    for (final requestedVersion in versions) {
      final version = currentScript.versions
          .where((candidate) => candidate.id == requestedVersion.id)
          .firstOrNull;
      if (version == null || !canDeleteVersion(currentScript, version)) {
        continue;
      }
      targetVersionsById[version.id] = version;
    }
    if (targetVersionsById.isEmpty) return;
    final deletedItems = [
      for (final version in targetVersionsById.values)
        for (final item in version.items)
          if (item.canDelete) item,
    ];
    for (final version in targetVersionsById.values) {
      await deleter(
        currentScript,
        version,
        deleteLocalFiles: deleteLocalFiles,
      );
    }
    final deletedVersionIds = targetVersionsById.keys.toSet();
    final selectionChanged = selectedScriptId == currentScript.scriptId &&
        selectedVersionId != null &&
        deletedVersionIds.contains(selectedVersionId);
    if (selectedScriptId == currentScript.scriptId &&
        selectedVersionId != null &&
        deletedVersionIds.contains(selectedVersionId)) {
      selectedVersionId = null;
      selectedDetailFilterId = allDetailFilterId;
      focusedItemId = null;
    }
    _selectedVersionIds.removeAll(deletedVersionIds);
    final snapshotChanged =
        _removeVersionsFromCurrentSnapshot(currentScript, deletedVersionIds);
    if (selectionChanged || snapshotChanged) {
      notifyListeners();
    }
    _refreshAfterVersionDelete(deletedItems);
  }

  bool _removeVersionsFromCurrentSnapshot(
    ScriptExhibitionScript target,
    Set<String> versionIds,
  ) {
    if (versionIds.isEmpty) return false;
    var changed = false;
    final nextScripts = <ScriptExhibitionScript>[];
    for (final script in snapshot.scripts) {
      if (!_scriptMatchesForLocalMutation(script, target)) {
        nextScripts.add(script);
        continue;
      }
      final nextScript = _scriptWithoutVersions(script, versionIds);
      changed = true;
      if (nextScript != null) {
        nextScripts.add(nextScript);
      }
    }
    if (!changed) {
      return false;
    }
    _setSnapshot(_snapshotFromScripts(nextScripts));
    _normalizeSelection();
    return true;
  }

  bool _removeItemFromCurrentSnapshot(ScriptExhibitionItem target) {
    var changed = false;
    final nextScripts = <ScriptExhibitionScript>[];
    for (final script in snapshot.scripts) {
      final nextScript = _scriptWithoutItem(script, target.id);
      if (identical(nextScript, script)) {
        nextScripts.add(script);
        continue;
      }
      changed = true;
      if (nextScript != null) {
        nextScripts.add(nextScript);
      }
    }
    if (!changed) {
      return false;
    }
    _setSnapshot(_snapshotFromScripts(nextScripts));
    _normalizeSelection();
    return true;
  }

  void _refreshAfterVersionDelete(List<ScriptExhibitionItem> deletedItems) {
    if (_versionDeleteTouchesRecast(deletedItems)) {
      unawaited(load());
      return;
    }
    final reloadProductionPlans =
        deletedItems.any(_itemHasProductionTaskIdentity);
    final reloadGalleryRecords =
        deletedItems.any(_itemHasGalleryRecordIdentity);
    if (!reloadProductionPlans && !reloadGalleryRecords) {
      return;
    }
    unawaited(_refreshDynamicVersionSources(
      reloadProductionPlans: reloadProductionPlans,
      reloadGalleryRecords: reloadGalleryRecords,
    ));
  }

  Future<bool> _refreshAfterItemDelete(ScriptExhibitionItem deletedItem) async {
    final reloadProductionPlans = _itemHasProductionTaskIdentity(deletedItem);
    final reloadGalleryRecords = _itemHasGalleryRecordIdentity(deletedItem);
    if (!reloadProductionPlans && !reloadGalleryRecords) {
      return false;
    }
    await _refreshDynamicVersionSources(
      reloadProductionPlans: reloadProductionPlans,
      reloadGalleryRecords: reloadGalleryRecords,
    );
    return true;
  }

  Future<void> _refreshDynamicVersionSources({
    required bool reloadProductionPlans,
    required bool reloadGalleryRecords,
  }) async {
    final generation = _loadGeneration;
    try {
      final results = await Future.wait<Object>([
        if (reloadProductionPlans)
          loadProductionPlans()
        else
          Future<List<ProductionPlan>>.value(_loadedProductionPlans),
        if (reloadGalleryRecords)
          loadGalleryRecords()
        else
          Future<List<StudioGalleryRecord>>.value(_loadedGalleryRecords),
      ]);
      if (generation != _loadGeneration) {
        return;
      }
      final plans = results[0] as List<ProductionPlan>;
      final records = results[1] as List<StudioGalleryRecord>;
      _loadedProductionPlans = plans;
      _loadedGalleryRecords = records;
      final dynamicBuild = await _buildSnapshotForPublication(
        recastScripts: _loadedRecastScripts,
        scripts: _loadedScripts,
        plans: plans,
        records: records,
      );
      if (!_canPublishSnapshotBuild(
        generation: generation,
        revision: dynamicBuild.revision,
      )) {
        return;
      }
      _publishSnapshot(dynamicBuild.snapshot);
    } catch (error) {
      if (generation != _loadGeneration) {
        return;
      }
      loadError = error;
      notifyListeners();
    }
  }

  Future<void> refreshDynamicVersions({
    bool reloadProductionPlans = true,
    bool reloadGalleryRecords = true,
  }) {
    return _refreshDynamicVersionSources(
      reloadProductionPlans: reloadProductionPlans,
      reloadGalleryRecords: reloadGalleryRecords,
    );
  }

  Future<void> renameScript(
    ScriptExhibitionScript script,
    String label,
  ) async {
    final renamer = renameScriptRecord;
    final trimmed = label.trim();
    if (renamer == null || trimmed.isEmpty) return;
    await renamer(script, trimmed);
    await load();
  }

  Future<void> createCategory(String categoryName) async {
    final normalized = categoryName.trim();
    if (normalized.isEmpty) return;
    final creator = createCategoryRecord;
    if (creator != null) {
      await creator(normalized);
      _rememberLoadedCustomCategory(normalized);
    }
    _ensureSessionCategory(normalized);
    notifyListeners();
  }

  Future<void> assignScriptToCategory(
    ScriptExhibitionScript script,
    String categoryName,
  ) async {
    final normalized = categoryName.trim();
    if (normalized.isEmpty) return;
    await assignScriptsToCategory([script], normalized);
  }

  Future<void> assignScriptsToCategory(
    Iterable<ScriptExhibitionScript> scripts,
    String categoryName,
  ) async {
    final singleAssigner = assignScriptCategory;
    final batchAssigner = assignScriptsCategory;
    final normalized = categoryName.trim();
    if ((singleAssigner == null && batchAssigner == null) ||
        normalized.isEmpty) {
      return;
    }
    final uniqueScripts = <String, ScriptExhibitionScript>{};
    for (final script in scripts) {
      uniqueScripts[script.scriptId] = script;
    }
    if (uniqueScripts.isEmpty) return;
    final scriptsNeedingPersistence = <ScriptExhibitionScript>[
      for (final script in uniqueScripts.values)
        if (!_scriptHasCategory(
            _scriptsById[script.scriptId] ?? script, normalized))
          _scriptsById[script.scriptId] ?? script,
    ];
    final creator = createCategoryRecord;
    if (creator != null) {
      await creator(normalized);
      _rememberLoadedCustomCategory(normalized);
    }
    _ensureSessionCategory(normalized);
    _applyCategoryToLoadedSources(uniqueScripts.keys, normalized);
    _applyCategoryToSnapshot(uniqueScripts.keys, normalized);
    selectedScriptId = null;
    selectedVersionId = null;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    _selectedScriptIds.clear();
    _selectedVersionIds.clear();
    notifyListeners();
    if (scriptsNeedingPersistence.isEmpty) {
      return;
    }
    try {
      if (batchAssigner != null) {
        await batchAssigner(scriptsNeedingPersistence, normalized);
      } else {
        for (final script in scriptsNeedingPersistence) {
          await singleAssigner!(script, normalized);
        }
      }
      await _refreshCategoryAssignmentsFromPersistence();
    } catch (_) {
      await load();
      rethrow;
    }
  }

  Future<void> _refreshCategoryAssignmentsFromPersistence() async {
    final generation = _loadGeneration;
    final loadedCustomCategoryScriptIds = await loadCustomCategoryScriptIds();
    if (generation != _loadGeneration) {
      return;
    }
    _loadedCustomCategoryScriptIds = loadedCustomCategoryScriptIds;
    final categoryBuild = await _buildSnapshotForPublication(
      recastScripts: _loadedRecastScripts,
      scripts: _loadedScripts,
      plans: _loadedProductionPlans,
      records: _loadedGalleryRecords,
    );
    if (!_canPublishSnapshotBuild(
      generation: generation,
      revision: categoryBuild.revision,
    )) {
      return;
    }
    _publishSnapshot(categoryBuild.snapshot);
  }

  String? selectedCategoryNameForScript(ScriptExhibitionScript script) {
    final categoryName = _selectedCustomCategoryName();
    if (categoryName == null) return null;
    if (!_scriptHasCategory(script, categoryName)) return null;
    return categoryName;
  }

  bool canRemoveScriptFromSelectedCategory(ScriptExhibitionScript script) {
    return removeScriptCategory != null &&
        selectedCategoryNameForScript(script) != null;
  }

  Future<void> removeScriptFromSelectedCategory(
    ScriptExhibitionScript script,
  ) async {
    final remover = removeScriptCategory;
    final categoryName = selectedCategoryNameForScript(script);
    if (remover == null || categoryName == null) return;
    await remover(script, categoryName);
    if (selectedScriptId == script.scriptId) {
      selectedScriptId = null;
      selectedVersionId = null;
      selectedDetailFilterId = allDetailFilterId;
      focusedItemId = null;
      _selectedVersionIds.clear();
    }
    _selectedScriptIds.remove(script.scriptId);
    await load();
  }

  bool canDeleteCategory(ScriptExhibitionCategory category) {
    if (_isProtectedCategoryId(category.id)) return false;
    if (deleteCategoryRecord != null) return true;
    return _sessionCategories.any((session) => session.id == category.id);
  }

  bool canAssignCategory(ScriptExhibitionCategory category) {
    return assignScriptCategory != null && !_isProtectedCategoryId(category.id);
  }

  Future<void> deleteCategory(ScriptExhibitionCategory category) async {
    if (!canDeleteCategory(category)) return;
    final normalized = category.title.trim();
    if (normalized.isEmpty) return;
    _sessionCategories.removeWhere(
      (session) =>
          session.id == category.id ||
          session.title.trim().toLowerCase() == normalized.toLowerCase(),
    );
    _categoriesCache = null;
    final deleter = deleteCategoryRecord;
    if (deleter != null) {
      await deleter(normalized);
      await load();
    }
    if (selectedCategoryId == category.id) {
      selectedCategoryId = allCategoryId;
      selectedScriptId = null;
      selectedVersionId = null;
      selectedDetailFilterId = allDetailFilterId;
      focusedItemId = null;
      _selectedVersionIds.clear();
    }
    _selectedScriptIds.clear();
    notifyListeners();
  }

  Future<void> renameItem(
    ScriptExhibitionItem item,
    String label,
  ) async {
    final renamer = renameImageAttachment;
    if (renamer == null || !item.canRename) return;
    await renamer(item, label);
    await load();
  }

  Future<void> renameVersionLabel(
    ScriptExhibitionScript script,
    ScriptExhibitionVersion version,
    String label,
  ) async {
    final renamer = renameVersionLabelRecord;
    final trimmed = label.trim();
    if (renamer == null || trimmed.isEmpty) return;
    await renamer(script, version, trimmed);
    _applyVersionLabelToLoadedSources(script, version.id, trimmed);
    if (_applyVersionLabelToCurrentSnapshot(script, version.id, trimmed)) {
      notifyListeners();
    }
  }

  Future<void> setCoverItem(ScriptExhibitionItem item) async {
    final setter = setCoverItemRecord;
    if (setter == null || !item.hasImage) return;
    await setter(item);
    await load();
    focusedItemId = item.id;
    notifyListeners();
  }

  Future<({int revision, ScriptExhibitionSnapshot snapshot})>
      _buildSnapshotForPublication({
    required List<RecastExhibitionScript> recastScripts,
    required List<TokenizerScript> scripts,
    required List<ProductionPlan> plans,
    required List<StudioGalleryRecord> records,
  }) async {
    final revision = ++_snapshotBuildRevision;
    final snapshot = await _snapshotBuilder(
      recastScripts: recastScripts,
      scripts: scripts,
      plans: plans,
      records: records,
    );
    return (revision: revision, snapshot: snapshot);
  }

  bool _canPublishSnapshotBuild({
    required int generation,
    required int revision,
  }) {
    return generation == _loadGeneration && revision == _snapshotBuildRevision;
  }

  void _publishSnapshot(ScriptExhibitionSnapshot nextSnapshot) {
    _setSnapshot(nextSnapshot, invalidatePendingBuilds: false);
    _normalizeSelection();
    notifyListeners();
    _ensureSelectedScriptDetailLoaded();
  }

  void _ensureSelectedScriptDetailLoaded() {
    final script = selectedScript;
    if (script == null || !script.summaryOnly) return;
    unawaited(_loadScriptDetailIfNeeded(script.scriptId));
  }

  void _setSnapshot(
    ScriptExhibitionSnapshot nextSnapshot, {
    bool invalidatePendingBuilds = true,
  }) {
    if (invalidatePendingBuilds) {
      _snapshotBuildRevision += 1;
    }
    _snapshot = nextSnapshot;
    final scriptsById = <String, ScriptExhibitionScript>{};
    final itemsById = <String, ScriptExhibitionItem>{};
    final scriptsByCategoryName = <String, List<ScriptExhibitionScript>>{};
    final assignedCustomScriptIds = <String>{
      for (final entry in _effectiveCustomCategoryScriptIds.entries)
        if (!_isProtectedCategoryId(entry.key)) ...entry.value,
    };
    final uncategorizedScripts = <ScriptExhibitionScript>[];
    final activeScripts = <ScriptExhibitionScript>[];
    final archivedScripts = <ScriptExhibitionScript>[];
    final needsActionScripts = <ScriptExhibitionScript>[];
    for (final script in nextSnapshot.scripts) {
      scriptsById[script.scriptId] = script;
      switch (script.status) {
        case ScriptExhibitionScriptStatus.active:
          activeScripts.add(script);
          break;
        case ScriptExhibitionScriptStatus.archived:
          archivedScripts.add(script);
          break;
        case ScriptExhibitionScriptStatus.needsAction:
          needsActionScripts.add(script);
          break;
      }
      var hasCustomCategory = assignedCustomScriptIds.contains(script.scriptId);
      for (final categoryName in script.categoryNames) {
        final normalized = categoryName.trim().toLowerCase();
        if (normalized.isNotEmpty) {
          hasCustomCategory = true;
          scriptsByCategoryName.putIfAbsent(normalized, () => []).add(script);
        }
      }
      if (!hasCustomCategory) {
        uncategorizedScripts.add(script);
      }
      for (final version in script.versions) {
        for (final item in version.items) {
          itemsById[item.id] = item;
        }
      }
    }
    _scriptsById = Map.unmodifiable(scriptsById);
    _itemsById = Map.unmodifiable(itemsById);
    _scriptsByCategoryName =
        Map<String, List<ScriptExhibitionScript>>.unmodifiable({
      for (final entry in scriptsByCategoryName.entries)
        entry.key: List<ScriptExhibitionScript>.unmodifiable(entry.value),
    });
    _uncategorizedScripts = List.unmodifiable(uncategorizedScripts);
    _activeScripts = List.unmodifiable(activeScripts);
    _archivedScripts = List.unmodifiable(archivedScripts);
    _needsActionScripts = List.unmodifiable(needsActionScripts);
    _categoriesCache = null;
  }

  void _normalizeSelection() {
    if (selectedScriptId != null &&
        !_scriptsById.containsKey(selectedScriptId)) {
      selectedScriptId = null;
      selectedVersionId = null;
      selectedDetailFilterId = allDetailFilterId;
      focusedItemId = null;
      _selectedVersionIds.clear();
    }
    final script = selectedScript;
    if (script != null &&
        selectedVersionId != null &&
        !script.versions.any((version) => version.id == selectedVersionId)) {
      selectedVersionId = script.versions.firstOrNull?.id;
    }
    if (script == null) {
      _selectedVersionIds.clear();
    } else {
      final deletableVersionIds = {
        for (final version in script.versions)
          if (canDeleteVersion(script, version)) version.id,
      };
      _selectedVersionIds.removeWhere(
        (versionId) => !deletableVersionIds.contains(versionId),
      );
    }
    if (focusedItemId != null && focusedItem == null) {
      focusedItemId = null;
    }
    _selectedScriptIds.removeWhere(
      (scriptId) => !_scriptsById.containsKey(scriptId),
    );
    if (!detailFilters.any((filter) => filter.id == selectedDetailFilterId)) {
      selectedDetailFilterId = allDetailFilterId;
    }
  }

  void _restoreSelectionIfPresent({
    required String? scriptId,
    required String? versionId,
  }) {
    if (scriptId == null || !_scriptsById.containsKey(scriptId)) {
      return;
    }
    selectedScriptId = scriptId;
    _selectedVersionIds.clear();
    if (versionId != null &&
        selectedScript?.versions.any((version) => version.id == versionId) ==
            true) {
      selectedVersionId = versionId;
    }
    _normalizeSelection();
    notifyListeners();
  }

  void _normalizeShelfSelectionForVisibleScripts() {
    if (_selectedScriptIds.isEmpty) return;
    final visibleIds = visibleScripts.map((script) => script.scriptId).toSet();
    _selectedScriptIds
        .removeWhere((scriptId) => !visibleIds.contains(scriptId));
  }

  List<ScriptExhibitionScript> _scriptsForCustomCategory(String categoryId) {
    final scriptsById = <String, ScriptExhibitionScript>{};
    final categoryName = _customCategoryNameFromId(categoryId);
    if (categoryName != null) {
      for (final script in _scriptsByCategoryName[categoryName] ?? const []) {
        scriptsById[script.scriptId] = script;
      }
    }
    final assignedIds = _effectiveCustomCategoryScriptIds[categoryId];
    if (assignedIds != null) {
      for (final script in _scriptsForAssignedIds(assignedIds)) {
        scriptsById[script.scriptId] = script;
      }
    }
    if (scriptsById.isEmpty) return const [];
    return [
      for (final script in snapshot.scripts)
        if (scriptsById.containsKey(script.scriptId)) script,
    ];
  }

  List<ScriptExhibitionScript> _scriptsForAssignedIds(
    Iterable<String> assignedIds,
  ) {
    final assigned = assignedIds.toSet();
    if (assigned.isEmpty) return const [];
    return [
      for (final script in snapshot.scripts)
        if (assigned.contains(script.scriptId)) script,
    ];
  }

  void _applyCategoryToSnapshot(
    Iterable<String> scriptIds,
    String categoryName,
  ) {
    final normalized = categoryName.trim();
    if (normalized.isEmpty) return;
    final targetIds = scriptIds.toSet();
    if (targetIds.isEmpty) return;
    var changed = false;
    final nextScripts = [
      for (final script in snapshot.scripts)
        if (targetIds.contains(script.scriptId))
          () {
            if (_scriptHasCategory(script, normalized)) {
              return script;
            }
            changed = true;
            return script.copyWith(
              categoryNames: [...script.categoryNames, normalized],
            );
          }()
        else
          script,
    ];
    if (!changed) return;
    _setSnapshot(ScriptExhibitionSnapshot(
      scripts: List.unmodifiable(nextScripts),
      totalImageCount: snapshot.totalImageCount,
      generatedImageCount: snapshot.generatedImageCount,
      needsActionCount: snapshot.needsActionCount,
    ));
  }

  void _applyCategoryToLoadedSources(
    Iterable<String> scriptIds,
    String categoryName,
  ) {
    final normalized = categoryName.trim();
    if (normalized.isEmpty) return;
    final targetIds = scriptIds.toSet();
    if (targetIds.isEmpty) return;
    _loadedRecastScripts = [
      for (final script in _loadedRecastScripts)
        if (targetIds.contains(script.scriptId))
          script.copyWith(
            categoryNames:
                _categoryNamesWithAdded(script.categoryNames, normalized),
          )
        else
          script,
    ];
    _loadedScripts = [
      for (final script in _loadedScripts)
        if (targetIds.contains(script.scriptId))
          script.copyWith(
            categoryNames:
                _categoryNamesWithAdded(script.categoryNames, normalized),
          )
        else
          script,
    ];
  }

  bool _applyVersionLabelToCurrentSnapshot(
    ScriptExhibitionScript target,
    String versionId,
    String label,
  ) {
    final normalizedVersionId = versionId.trim();
    final normalizedLabel = label.trim();
    if (normalizedVersionId.isEmpty || normalizedLabel.isEmpty) {
      return false;
    }
    var changed = false;
    final nextScripts = [
      for (final script in snapshot.scripts)
        if (_scriptMatchesForLocalMutation(script, target))
          () {
            final nextScript = _scriptWithVersionLabel(
              script,
              versionId: normalizedVersionId,
              label: normalizedLabel,
            );
            changed = changed || !identical(nextScript, script);
            return nextScript;
          }()
        else
          script,
    ];
    if (!changed) {
      return false;
    }
    _setSnapshot(_snapshotFromScripts(nextScripts));
    _normalizeSelection();
    return true;
  }

  void _applyVersionLabelToLoadedSources(
    ScriptExhibitionScript target,
    String versionId,
    String label,
  ) {
    final normalizedVersionId = versionId.trim();
    final normalizedLabel = label.trim();
    if (normalizedVersionId.isEmpty || normalizedLabel.isEmpty) {
      return;
    }
    _loadedRecastScripts = [
      for (final script in _loadedRecastScripts)
        if (_sourceScriptMatchesTarget(
          scriptId: script.scriptId,
          title: script.scriptName,
          sourceFolder: script.sourceRootPath,
          target: target,
        ))
          script.copyWith(
            versionLabels: {
              ...script.versionLabels,
              normalizedVersionId: normalizedLabel,
            },
          )
        else
          script,
    ];
    _loadedScripts = [
      for (final script in _loadedScripts)
        if (_sourceScriptMatchesTarget(
          scriptId: script.scriptId,
          title: script.name,
          sourceFolder: script.sourceFolder,
          target: target,
        ))
          script.copyWith(
            exhibitionVersionLabels: {
              ...script.exhibitionVersionLabels,
              normalizedVersionId: normalizedLabel,
            },
          )
        else
          script,
    ];
  }

  List<ScriptExhibitionUserCategory> _registeredCustomCategories() {
    final categoriesById = <String, ScriptExhibitionUserCategory>{};
    for (final category in customCategories) {
      categoriesById[category.id] = category;
    }
    for (final category in _loadedCustomCategories) {
      categoriesById.putIfAbsent(category.id, () => category);
    }
    final categories = categoriesById.values.toList(growable: false)
      ..sort((left, right) => left.title.compareTo(right.title));
    return categories;
  }

  List<ScriptExhibitionUserCategory> _derivedCustomCategories() {
    final categoriesById = <String, ScriptExhibitionUserCategory>{};
    for (final category in _sessionCategories) {
      categoriesById[category.id] = category;
    }
    for (final script in snapshot.scripts) {
      for (final categoryName in script.categoryNames) {
        final normalized = categoryName.trim();
        if (normalized.isEmpty) continue;
        final id = _customCategoryId(normalized);
        categoriesById[id] = ScriptExhibitionUserCategory(
          id: id,
          title: normalized,
          description: '手动归入的剧本。',
          tags: const ['自由分类'],
        );
      }
    }
    for (final entry in _effectiveCustomCategoryScriptIds.entries) {
      if (_isProtectedCategoryId(entry.key) || entry.value.isEmpty) {
        continue;
      }
      final displayName = _customCategoryDisplayNameFromId(entry.key);
      if (displayName == null) {
        continue;
      }
      categoriesById.putIfAbsent(
        entry.key,
        () => ScriptExhibitionUserCategory(
          id: entry.key,
          title: displayName,
          description: 'Manual script category.',
          tags: const ['Manual'],
        ),
      );
    }
    for (final category in _registeredCustomCategories()) {
      categoriesById.remove(category.id);
    }
    final categories = categoriesById.values.toList()
      ..sort((left, right) => left.title.compareTo(right.title));
    return categories;
  }

  void _ensureSessionCategory(String categoryName) {
    final normalized = categoryName.trim();
    final id = _customCategoryId(normalized);
    if (_registeredCustomCategories().any((category) => category.id == id) ||
        _sessionCategories.any((category) => category.id == id)) {
      return;
    }
    _sessionCategories.add(
      ScriptExhibitionUserCategory(
        id: id,
        title: normalized,
        description: '手动归入的剧本。',
        tags: const ['自由分类'],
      ),
    );
    _categoriesCache = null;
  }

  void _rememberLoadedCustomCategory(String categoryName) {
    final normalized = categoryName.trim();
    if (normalized.isEmpty) return;
    final id = _customCategoryId(normalized);
    if (_loadedCustomCategories.any((category) => category.id == id)) {
      return;
    }
    _loadedCustomCategories = [
      ..._loadedCustomCategories,
      ScriptExhibitionUserCategory(
        id: id,
        title: normalized,
        description: '手动归入的剧本。',
        tags: const ['自由分类'],
      ),
    ];
    _categoriesCache = null;
  }

  String? _selectedCustomCategoryName() {
    if (_isProtectedCategoryId(selectedCategoryId)) return null;
    final matchingCategory = categories
        .where((category) => category.id == selectedCategoryId)
        .firstOrNull;
    final categoryTitle = matchingCategory?.title.trim();
    if (categoryTitle != null && categoryTitle.isNotEmpty) {
      return categoryTitle;
    }
    return _customCategoryDisplayNameFromId(selectedCategoryId);
  }
}

String _customCategoryId(String categoryName) =>
    'custom:${categoryName.trim()}';

bool _isProtectedCategoryId(String categoryId) {
  return switch (categoryId) {
    ScriptExhibitionRoomViewModel.allCategoryId ||
    ScriptExhibitionRoomViewModel.uncategorizedCategoryId ||
    ScriptExhibitionRoomViewModel.activeCategoryId ||
    ScriptExhibitionRoomViewModel.archivedCategoryId ||
    ScriptExhibitionRoomViewModel.needsActionCategoryId =>
      true,
    _ => false,
  };
}

String? _customCategoryNameFromId(String categoryId) {
  const prefix = 'custom:';
  if (!categoryId.startsWith(prefix)) return null;
  final value = categoryId.substring(prefix.length).trim().toLowerCase();
  return value.isEmpty ? null : value;
}

String? _customCategoryDisplayNameFromId(String categoryId) {
  const prefix = 'custom:';
  if (!categoryId.startsWith(prefix)) return null;
  final value = categoryId.substring(prefix.length).trim();
  return value.isEmpty ? null : value;
}

bool _scriptHasCategory(
  ScriptExhibitionScript script,
  String categoryName,
) {
  final normalized = categoryName.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return script.categoryNames.any(
    (name) => name.trim().toLowerCase() == normalized,
  );
}

List<String> _categoryNamesWithAdded(
  List<String> categoryNames,
  String categoryName,
) {
  final normalized = categoryName.trim();
  if (normalized.isEmpty) return categoryNames;
  final next = [
    for (final name in categoryNames)
      if (name.trim().isNotEmpty) name,
  ];
  if (!next
      .any((name) => name.trim().toLowerCase() == normalized.toLowerCase())) {
    next.add(normalized);
  }
  return List.unmodifiable(next);
}

ScriptExhibitionSnapshot _buildSnapshot({
  required List<RecastExhibitionScript> recastScripts,
  required List<TokenizerScript> scripts,
  required List<ProductionPlan> plans,
  required List<StudioGalleryRecord> records,
}) {
  final buckets = <_MutableScriptBucket>[];
  final bucketsByStrongAlias = <String, _MutableScriptBucket>{};
  final bucketsByTitleAlias = <String, _MutableScriptBucket?>{};
  final generatedProductionTasksByKey = <String, List<ProductionTask>>{};
  final galleryRecordsByProductionTaskKey =
      _galleryRecordsByProductionTaskKey(records);
  final imagePathIndexesByRoot = <String, Map<String, String>>{};

  _ImagePathsByLeafProvider imagePathsByLeafForRoot(String? rootPath) {
    final normalized = rootPath?.trim();
    if (normalized == null || normalized.isEmpty) {
      return () => const {};
    }
    return () => imagePathIndexesByRoot.putIfAbsent(
          normalized,
          () => _imagePathsByLeaf(normalized),
        );
  }

  void registerAliases(
    _MutableScriptBucket bucket, {
    required String? scriptId,
    required String? title,
    required String? sourceFolder,
  }) {
    for (final alias in _scriptStrongAliases(
      scriptId: scriptId,
      sourceFolder: sourceFolder,
    )) {
      bucketsByStrongAlias[alias] = bucket;
    }

    final titleAlias = _scriptTitleAlias(title);
    if (titleAlias == null) return;
    final current = bucketsByTitleAlias[titleAlias];
    if (!bucketsByTitleAlias.containsKey(titleAlias)) {
      bucketsByTitleAlias[titleAlias] = bucket;
      return;
    }
    if (current != null && !identical(current, bucket)) {
      bucketsByTitleAlias[titleAlias] = null;
    }
  }

  _MutableScriptBucket bucketFor({
    required String? scriptId,
    required String? title,
    required String? sourceFolder,
    String? sourceFileName,
    int? frameIndex,
    DateTime? updatedAt,
  }) {
    final normalizedId = _firstNonEmpty([scriptId, sourceFolder, title]);
    if (normalizedId == null) {
      throw StateError('Script exhibition item is missing script identity.');
    }
    final strongBucket = _findStrongScriptBucket(
      scriptId: scriptId,
      sourceFolder: sourceFolder,
      bucketsByStrongAlias: bucketsByStrongAlias,
    );
    final weakBucket = strongBucket == null
        ? _findWeakScriptBucket(
            title: title,
            sourceFolder: sourceFolder,
            sourceFileName: sourceFileName,
            frameIndex: frameIndex,
            bucketsByTitleAlias: bucketsByTitleAlias,
          )
        : null;
    var bucket = strongBucket ?? weakBucket;
    final matchedWeakBucket = strongBucket == null && weakBucket != null;
    if (bucket == null) {
      bucket = _MutableScriptBucket(
        scriptId: normalizedId,
        title: _fallback(title, '未命名剧本'),
        sourceFolder: sourceFolder ?? '',
        updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
      buckets.add(bucket);
    }
    final preserveExistingSourceFolder = matchedWeakBucket &&
        _hasText(bucket.sourceFolder) &&
        _hasText(sourceFolder);
    bucket.merge(
      title: title,
      sourceFolder: preserveExistingSourceFolder ? null : sourceFolder,
      updatedAt: updatedAt,
    );
    registerAliases(
      bucket,
      scriptId: preserveExistingSourceFolder ? null : scriptId,
      title: title,
      sourceFolder: preserveExistingSourceFolder ? null : sourceFolder,
    );
    return bucket;
  }

  for (final script in recastScripts) {
    final scriptId = script.scriptId;
    final sourceFolder = script.sourceRootPath;
    final bucket = bucketFor(
      scriptId: scriptId,
      title: script.scriptName,
      sourceFolder: sourceFolder,
      updatedAt: script.updatedAt,
    );
    final imagePathsByLeaf = imagePathsByLeafForRoot(sourceFolder);
    bucket.mergeCategories(script.categoryNames);
    bucket.mergeVersionLabels(script.versionLabels);
    bucket.mergeCoverItemId(script.coverItemId);
    if (script.summaryOnly) {
      bucket.markSummaryOnly();
      final hasKnownOriginalImage = script.frames.any(
        (frame) => _knownImagePathForRecastFrame(frame).isNotEmpty,
      );
      if (hasKnownOriginalImage) {
        final syntheticOriginalCount = script.displayFrameCount -
            script.frames.length -
            script.imageAttachments.length;
        if (syntheticOriginalCount > 0) {
          bucket.addSyntheticOriginalImageCount(syntheticOriginalCount);
        }
      }
    }
    final sourceVersionLabel = _recastSourceVersionLabel(script);
    final sourceVersionDescription = _recastSourceVersionDescription(script);
    for (final frame in script.frames) {
      bucket.addItem(
        ScriptExhibitionItem(
          id: 'original-${bucket.scriptId}-frame-${frame.index}',
          scriptId: bucket.scriptId,
          scriptTitle: bucket.title,
          sourceFolder: bucket.sourceFolder,
          versionId: ScriptExhibitionVersion.originalId,
          versionLabel: sourceVersionLabel,
          sourceKind: ScriptExhibitionItemSourceKind.original,
          frameIndex: frame.index,
          sourceFileName: frame.fileName,
          sourcePath: frame.sourcePath,
          title: _frameTitle(frame.index, frame.fileName),
          subtitle: _recastFrameStatusLabel(frame.parseStatus),
          prompt: frame.prompt,
          imagePath: script.summaryOnly
              ? _knownImagePathForRecastFrame(frame)
              : _imagePathForRecastFrame(
                  frame,
                  imagePathsByLeaf: imagePathsByLeaf,
                ),
          statusLabel: _recastFrameStatusLabel(frame.parseStatus),
          updatedAt: script.updatedAt,
          generationParams: frame.generationParams,
        ),
        versionDescription: sourceVersionDescription,
        versionUpdatedAt: script.updatedAt,
      );
    }
    for (final attachment in script.imageAttachments) {
      if (attachment.versionId.trim().isEmpty) {
        continue;
      }
      final attachmentVersionId = _attachmentVersionId(attachment);
      final attachmentVersionLabel = _attachmentVersionLabel(attachment);
      final attachmentPayload = attachment.payload.isEmpty
          ? null
          : Map<String, dynamic>.unmodifiable(attachment.payload);
      bucket.addItem(
        ScriptExhibitionItem(
          id: 'attachment-${bucket.scriptId}-${attachment.attachmentId}',
          scriptId: bucket.scriptId,
          scriptTitle: bucket.title,
          sourceFolder: bucket.sourceFolder,
          versionId: attachmentVersionId,
          versionLabel: attachmentVersionLabel,
          sourceKind: ScriptExhibitionItemSourceKind.attachment,
          frameIndex: attachment.frameIndex,
          sourceFileName: attachment.sourceFileName,
          title: _fallback(
            attachment.label,
            _fileNameFromPath(attachment.imagePath),
          ),
          subtitle: 'Attached image - ${_dateLabel(attachment.createdAt)}',
          prompt: _firstNonEmpty([
                attachment.prompt,
                if (attachmentPayload != null)
                  _payloadPrompt(attachmentPayload),
              ]) ??
              '',
          imagePath: attachment.imagePath,
          statusLabel: 'Attached',
          updatedAt: attachment.createdAt,
          assetCapturePayload: attachmentPayload,
          imageAttachmentId: attachment.attachmentId,
        ),
        versionDescription: 'Imported image version.',
        versionUpdatedAt: attachment.createdAt,
      );
    }
  }

  for (final script in scripts) {
    final bucket = bucketFor(
      scriptId: script.scriptId,
      title: script.name,
      sourceFolder: script.sourceFolder,
      updatedAt: script.updatedAt,
    );
    final imagePathsByLeaf = imagePathsByLeafForRoot(script.sourceFolder);
    bucket.mergeCategories(script.categoryNames);
    bucket.mergeVersionLabels(script.exhibitionVersionLabels);
    bucket.mergeCoverItemId(script.exhibitionCoverItemId);
    final sourceVersionLabel = _sourceVersionLabel(script);
    final sourceVersionDescription = _sourceVersionDescription(script);
    final usedSourceFileIds = <String>{};
    final sourceIndexes = {
      for (final (index, sourceFile) in script.sourceFiles.indexed)
        sourceFile.fileId: index + 1,
    };
    for (final (index, task) in script.imageTasks.indexed) {
      final frameIndex = sourceIndexes[task.sourceFile.fileId] ?? index + 1;
      final statusLabel = _tokenizerStatusLabel(task.reviewStatus);
      usedSourceFileIds.add(task.sourceFile.fileId);
      bucket.addItem(
        ScriptExhibitionItem(
          id: 'original-${script.scriptId}-${task.taskId}',
          scriptId: bucket.scriptId,
          scriptTitle: bucket.title,
          sourceFolder: bucket.sourceFolder,
          versionId: ScriptExhibitionVersion.originalId,
          versionLabel: sourceVersionLabel,
          sourceKind: ScriptExhibitionItemSourceKind.original,
          frameIndex: frameIndex,
          sourceFileName: task.sourceFile.fileName,
          sourcePath: task.sourceFile.path,
          title: _frameTitle(frameIndex, task.sourceFile.fileName),
          subtitle: statusLabel,
          prompt: _firstNonEmpty([task.originalPrompt, task.finalPrompt]) ?? '',
          imagePath: _defaultImagePathForSource(
            task.sourceFile,
            imagePathsByLeaf: imagePathsByLeaf,
          ),
          statusLabel: statusLabel,
          updatedAt: script.updatedAt,
          generationParams: task.generationParams,
        ),
        versionDescription: sourceVersionDescription,
        versionUpdatedAt: script.updatedAt,
      );
    }
    for (final (index, sourceFile) in script.sourceFiles.indexed) {
      if (usedSourceFileIds.contains(sourceFile.fileId)) {
        continue;
      }
      final frameIndex = index + 1;
      bucket.addItem(
        ScriptExhibitionItem(
          id: 'original-${script.scriptId}-${sourceFile.fileId}',
          scriptId: bucket.scriptId,
          scriptTitle: bucket.title,
          sourceFolder: bucket.sourceFolder,
          versionId: ScriptExhibitionVersion.originalId,
          versionLabel: sourceVersionLabel,
          sourceKind: ScriptExhibitionItemSourceKind.original,
          frameIndex: frameIndex,
          sourceFileName: sourceFile.fileName,
          sourcePath: sourceFile.path,
          title: _frameTitle(frameIndex, sourceFile.fileName),
          subtitle: sourceFile.exists ? '源文件' : '源文件缺失',
          prompt: '',
          imagePath: _defaultImagePathForSource(
            sourceFile,
            imagePathsByLeaf: imagePathsByLeaf,
          ),
          statusLabel: sourceFile.exists ? '源文件' : '源文件缺失',
          updatedAt: script.updatedAt,
        ),
        versionDescription: sourceVersionDescription,
        versionUpdatedAt: script.updatedAt,
      );
    }
    for (final attachment in script.imageAttachments) {
      if (attachment.versionId.trim().isEmpty) {
        continue;
      }
      final attachmentVersionId = _attachmentVersionId(attachment);
      final attachmentVersionLabel = _attachmentVersionLabel(attachment);
      final attachmentPayload = attachment.payload.isEmpty
          ? null
          : Map<String, dynamic>.unmodifiable(attachment.payload);
      bucket.addItem(
        ScriptExhibitionItem(
          id: 'attachment-${script.scriptId}-${attachment.attachmentId}',
          scriptId: bucket.scriptId,
          scriptTitle: bucket.title,
          sourceFolder: bucket.sourceFolder,
          versionId: attachmentVersionId,
          versionLabel: attachmentVersionLabel,
          sourceKind: ScriptExhibitionItemSourceKind.attachment,
          frameIndex: attachment.frameIndex,
          sourceFileName: attachment.sourceFileName,
          title: _fallback(
              attachment.label, _fileNameFromPath(attachment.imagePath)),
          subtitle: '挂接图片 · ${_dateLabel(attachment.createdAt)}',
          prompt: _firstNonEmpty([
                attachment.prompt,
                if (attachmentPayload != null)
                  _payloadPrompt(attachmentPayload),
              ]) ??
              '',
          imagePath: attachment.imagePath,
          statusLabel: '已挂接',
          updatedAt: attachment.createdAt,
          assetCapturePayload: attachmentPayload,
          imageAttachmentId: attachment.attachmentId,
        ),
        versionDescription: '按顺序导入并读取 JSON 数据的图片版本。',
        versionUpdatedAt: attachment.createdAt,
      );
    }
  }

  for (final plan in plans) {
    for (final task in plan.tasks) {
      final source = task.source;
      final scriptKey = _firstNonEmpty([
        source.scriptId,
        source.scriptPath,
        source.scriptName,
      ]);
      if (scriptKey == null) continue;
      final bucket = bucketFor(
        scriptId: source.scriptId ?? scriptKey,
        title: source.scriptName,
        sourceFolder: source.scriptPath,
        sourceFileName: source.sourceFileName,
        frameIndex: source.frameIndex,
        updatedAt: plan.updatedAt,
      );
      final kind = _productionKind(task.status);
      final imagePath = task.outputImagePath ?? '';
      final galleryRecord = kind == ScriptExhibitionItemSourceKind.generated
          ? _matchingGalleryRecordForTask(
              planId: plan.id,
              task: task,
              recordsByProductionTaskKey: galleryRecordsByProductionTaskKey,
            )
          : null;
      final displayImagePath = _firstNonEmpty([
            imagePath,
            galleryRecord?.imagePath,
            galleryRecord?.provenance?.outputImagePath,
          ]) ??
          '';
      final assetCapturePayload = _lightweightProductionPayload(task.payload);
      final generationParams = _lightweightProductionParameters(
        task.payload['parameters'] ?? task.payload['param_config'],
      );
      if (kind == ScriptExhibitionItemSourceKind.generated &&
          displayImagePath.trim().isNotEmpty) {
        final key = _productionTaskProvenanceKey(plan.id, task.id);
        generatedProductionTasksByKey.putIfAbsent(key, () => []).add(task);
      }
      bucket.addItem(
        ScriptExhibitionItem(
          id: 'production-${plan.id}-${task.id}',
          scriptId: bucket.scriptId,
          scriptTitle: bucket.title,
          sourceFolder: bucket.sourceFolder,
          versionId: 'production-${plan.id}',
          versionLabel: plan.name,
          sourceKind: kind,
          frameIndex: source.frameIndex,
          sourceFileName: source.sourceFileName,
          title: kind == ScriptExhibitionItemSourceKind.generated
              ? '新图: ${task.title}'
              : task.title,
          subtitle: _productionStatusLabel(task),
          prompt: _payloadPrompt(assetCapturePayload ?? const {}),
          imagePath: displayImagePath,
          statusLabel: _productionStatusLabel(task),
          updatedAt: task.updatedAt,
          productionPlanId: plan.id,
          recastRunId: source.recastRunId,
          taskId: task.id,
          galleryRecord: galleryRecord,
          assetCapturePayload: assetCapturePayload,
          generationParams: generationParams,
        ),
        versionDescription: source.recastRunId == null
            ? '批量产线版本。'
            : '批量产线版本 · ${source.recastRunId}',
        versionUpdatedAt: plan.updatedAt,
      );
    }
  }

  for (final record in records) {
    final provenance = record.provenance;
    if (provenance == null) continue;
    final productionTasks =
        generatedProductionTasksByKey[_productionTaskProvenanceKey(
      provenance.productionPlanId,
      provenance.taskId,
    )];
    if (productionTasks != null &&
        productionTasks.any(
          (task) => _matchesProductionTaskProvenance(
            task.source,
            provenance,
          ),
        )) {
      continue;
    }
    final scriptKey = _firstNonEmpty([
      provenance.scriptId,
      provenance.scriptPath,
      provenance.scriptName,
    ]);
    if (scriptKey == null) continue;
    final bucket = bucketFor(
      scriptId: provenance.scriptId ?? scriptKey,
      title: provenance.scriptName,
      sourceFolder: provenance.scriptPath,
      sourceFileName: provenance.sourceFileName,
      frameIndex: provenance.frameIndex,
      updatedAt: record.createdAt,
    );
    bucket.addItem(
      ScriptExhibitionItem(
        id: 'gallery-${record.id}',
        scriptId: bucket.scriptId,
        scriptTitle: bucket.title,
        sourceFolder: bucket.sourceFolder,
        versionId: ScriptExhibitionVersion.galleryId,
        versionLabel: '已收纳',
        sourceKind: ScriptExhibitionItemSourceKind.gallery,
        frameIndex: provenance.frameIndex,
        sourceFileName: provenance.sourceFileName,
        title: record.title.trim().isEmpty ? '已收纳图片' : record.title,
        subtitle: '画廊记录 · ${_dateLabel(record.createdAt)}',
        prompt: record.info,
        imagePath: _firstNonEmpty([
              record.imagePath,
              provenance.outputImagePath,
            ]) ??
            '',
        statusLabel: '已收纳',
        updatedAt: record.createdAt,
        productionPlanId: provenance.productionPlanId,
        recastRunId: provenance.recastRunId,
        taskId: provenance.taskId,
        galleryRecordId: record.id,
        galleryRecord: record,
      ),
      versionDescription: '已保存到画廊的剧本结果。',
      versionUpdatedAt: record.createdAt,
    );
  }

  final scriptsOut = buckets
      .map((bucket) => bucket.toScript())
      .where((script) => script.hasImage)
      .toList()
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

  var totalImageCount = 0;
  var generatedImageCount = 0;
  var needsActionCount = 0;
  for (final script in scriptsOut) {
    totalImageCount += script.imageLikeItemCount;
    generatedImageCount += script.generatedImageCount;
    if (script.status == ScriptExhibitionScriptStatus.needsAction) {
      needsActionCount += 1;
    }
  }

  return ScriptExhibitionSnapshot(
    scripts: List.unmodifiable(scriptsOut),
    totalImageCount: totalImageCount,
    generatedImageCount: generatedImageCount,
    needsActionCount: needsActionCount,
  );
}

ScriptExhibitionSnapshot _snapshotFromScripts(
  Iterable<ScriptExhibitionScript> scripts,
) {
  final scriptsOut = scripts.where((script) => script.hasImage).toList()
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  var totalImageCount = 0;
  var generatedImageCount = 0;
  var needsActionCount = 0;
  for (final script in scriptsOut) {
    totalImageCount += script.imageLikeItemCount;
    generatedImageCount += script.generatedImageCount;
    if (script.status == ScriptExhibitionScriptStatus.needsAction) {
      needsActionCount += 1;
    }
  }
  return ScriptExhibitionSnapshot(
    scripts: List.unmodifiable(scriptsOut),
    totalImageCount: totalImageCount,
    generatedImageCount: generatedImageCount,
    needsActionCount: needsActionCount,
  );
}

ScriptExhibitionScript? _scriptWithoutVersions(
  ScriptExhibitionScript script,
  Set<String> versionIds,
) {
  var removed = false;
  var originalItemCount = 0;
  final remainingVersions = <ScriptExhibitionVersion>[];
  for (final version in script.versions) {
    if (version.id == ScriptExhibitionVersion.originalId) {
      originalItemCount += version.items.length;
    }
    if (versionIds.contains(version.id)) {
      removed = true;
      continue;
    }
    remainingVersions.add(version);
  }
  if (!removed) {
    return script;
  }
  if (remainingVersions.isEmpty) {
    return null;
  }
  final updatedAt = _latestVersionUpdatedAt(remainingVersions) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final bucket = _MutableScriptBucket(
    scriptId: script.scriptId,
    title: script.title,
    sourceFolder: script.sourceFolder,
    updatedAt: updatedAt,
  );
  bucket.mergeCategories(script.categoryNames);
  bucket.mergeCoverItemId(script.coverItemId);
  if (script.summaryOnly) {
    bucket.markSummaryOnly();
  }
  final syntheticOriginalImageCount = script.originalCount - originalItemCount;
  if (syntheticOriginalImageCount > 0) {
    bucket.addSyntheticOriginalImageCount(syntheticOriginalImageCount);
  }
  for (final version in remainingVersions) {
    for (final item in version.items) {
      bucket.addItem(
        item,
        versionDescription: version.description,
        versionUpdatedAt: version.updatedAt,
      );
    }
  }
  final nextScript = bucket.toScript();
  return nextScript.hasImage ? nextScript : null;
}

ScriptExhibitionScript? _scriptWithoutItem(
  ScriptExhibitionScript script,
  String itemId,
) {
  var removed = false;
  var originalItemCount = 0;
  final remainingVersions = <ScriptExhibitionVersion>[];
  for (final version in script.versions) {
    final remainingItems = <ScriptExhibitionItem>[];
    for (final item in version.items) {
      if (item.id == itemId) {
        removed = true;
        continue;
      }
      remainingItems.add(item);
    }
    if (remainingItems.isEmpty) {
      continue;
    }
    if (version.id == ScriptExhibitionVersion.originalId) {
      originalItemCount += remainingItems.length;
    }
    remainingVersions.add(
      ScriptExhibitionVersion(
        id: version.id,
        label: version.label,
        description: version.description,
        updatedAt: version.updatedAt,
        items: List.unmodifiable(remainingItems),
      ),
    );
  }
  if (!removed) {
    return script;
  }
  if (remainingVersions.isEmpty) {
    return null;
  }
  final updatedAt = _latestVersionUpdatedAt(remainingVersions) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final bucket = _MutableScriptBucket(
    scriptId: script.scriptId,
    title: script.title,
    sourceFolder: script.sourceFolder,
    updatedAt: updatedAt,
  );
  bucket.mergeCategories(script.categoryNames);
  bucket.mergeCoverItemId(script.coverItemId);
  if (script.summaryOnly) {
    bucket.markSummaryOnly();
  }
  final syntheticOriginalImageCount = script.originalCount - originalItemCount;
  if (syntheticOriginalImageCount > 0) {
    bucket.addSyntheticOriginalImageCount(syntheticOriginalImageCount);
  }
  for (final version in remainingVersions) {
    for (final item in version.items) {
      bucket.addItem(
        item,
        versionDescription: version.description,
        versionUpdatedAt: version.updatedAt,
      );
    }
  }
  final nextScript = bucket.toScript();
  return nextScript.hasImage ? nextScript : null;
}

ScriptExhibitionScript _scriptWithVersionLabel(
  ScriptExhibitionScript script, {
  required String versionId,
  required String label,
}) {
  final normalizedVersionId = versionId.trim();
  final normalizedLabel = label.trim();
  if (normalizedVersionId.isEmpty || normalizedLabel.isEmpty) {
    return script;
  }
  var changed = false;
  final nextVersions = [
    for (final version in script.versions)
      if (version.id == normalizedVersionId)
        () {
          if (version.label == normalizedLabel &&
              version.items.every(
                (item) => item.versionLabel == normalizedLabel,
              )) {
            return version;
          }
          changed = true;
          return ScriptExhibitionVersion(
            id: version.id,
            label: normalizedLabel,
            description: version.description,
            updatedAt: version.updatedAt,
            items: List.unmodifiable([
              for (final item in version.items)
                item.versionLabel == normalizedLabel
                    ? item
                    : item.copyWith(versionLabel: normalizedLabel),
            ]),
          );
        }()
      else
        version,
  ];
  if (!changed) {
    return script;
  }
  final nextItemsById = <String, ScriptExhibitionItem>{
    for (final version in nextVersions)
      for (final item in version.items) item.id: item,
  };
  ScriptExhibitionItem? rebaseItem(ScriptExhibitionItem? item) {
    if (item == null) return null;
    return nextItemsById[item.id] ?? item;
  }

  return ScriptExhibitionScript(
    scriptId: script.scriptId,
    title: script.title,
    sourceFolder: script.sourceFolder,
    updatedAt: script.updatedAt,
    versions: List.unmodifiable(nextVersions),
    status: script.status,
    categoryNames: script.categoryNames,
    coverItemId: script.coverItemId,
    originalCount: script.originalCount,
    generatedImageCount: script.generatedImageCount,
    imageLikeItemCount: script.imageLikeItemCount,
    hasImage: script.hasImage,
    coverItem: rebaseItem(script.coverItem),
    pendingCount: script.pendingCount,
    firstNeedsActionItem: rebaseItem(script.firstNeedsActionItem),
    summaryOnly: script.summaryOnly,
    searchText: _scriptSearchTextFromValues(
      scriptId: script.scriptId,
      title: script.title,
      sourceFolder: script.sourceFolder,
      categoryNames: script.categoryNames,
      versions: List.unmodifiable(nextVersions),
    ),
  );
}

DateTime? _latestVersionUpdatedAt(Iterable<ScriptExhibitionVersion> versions) {
  DateTime? latest;
  for (final version in versions) {
    if (latest == null || version.updatedAt.isAfter(latest)) {
      latest = version.updatedAt;
    }
  }
  return latest;
}

bool _scriptMatchesForLocalMutation(
  ScriptExhibitionScript script,
  ScriptExhibitionScript target,
) {
  return _sourceScriptMatchesTarget(
    scriptId: script.scriptId,
    title: script.title,
    sourceFolder: script.sourceFolder,
    target: target,
  );
}

bool _sourceScriptMatchesTarget({
  required String? scriptId,
  required String? title,
  required String? sourceFolder,
  required ScriptExhibitionScript target,
}) {
  final scriptAliases =
      _scriptStrongAliases(scriptId: scriptId, sourceFolder: sourceFolder)
          .toSet();
  final targetAliases = _scriptStrongAliases(
    scriptId: target.scriptId,
    sourceFolder: target.sourceFolder,
  ).toSet();
  if (scriptAliases.intersection(targetAliases).isNotEmpty) {
    return true;
  }
  if (scriptAliases.isNotEmpty || targetAliases.isNotEmpty) {
    return false;
  }
  final scriptTitle = _scriptTitleAlias(title);
  final targetTitle = _scriptTitleAlias(target.title);
  return scriptTitle != null && scriptTitle == targetTitle;
}

bool _versionDeleteTouchesRecast(Iterable<ScriptExhibitionItem> items) {
  return items.any((item) {
    final attachmentId = item.imageAttachmentId?.trim();
    return attachmentId != null && attachmentId.isNotEmpty;
  });
}

bool _itemDeleteTouchesRecast(ScriptExhibitionItem item) {
  final attachmentId = item.imageAttachmentId?.trim();
  return attachmentId != null && attachmentId.isNotEmpty;
}

bool _itemHasProductionTaskIdentity(ScriptExhibitionItem item) {
  final planId = item.productionPlanId?.trim();
  final taskId = item.taskId?.trim();
  return planId != null &&
      planId.isNotEmpty &&
      taskId != null &&
      taskId.isNotEmpty;
}

bool _itemHasGalleryRecordIdentity(ScriptExhibitionItem item) {
  final recordId = item.galleryRecordId?.trim();
  return recordId != null && recordId.isNotEmpty;
}

Future<ScriptExhibitionSnapshot> _buildSnapshotAsync({
  required List<RecastExhibitionScript> recastScripts,
  required List<TokenizerScript> scripts,
  required List<ProductionPlan> plans,
  required List<StudioGalleryRecord> records,
}) {
  if (!_shouldBuildSnapshotInBackground(
    recastScripts: recastScripts,
    scripts: scripts,
    plans: plans,
    records: records,
  )) {
    return Future.value(
      _buildSnapshot(
        recastScripts: recastScripts,
        scripts: scripts,
        plans: plans,
        records: records,
      ),
    );
  }
  return compute(
    _buildSnapshotFromRequest,
    _ScriptExhibitionSnapshotRequest(
      recastScripts: recastScripts,
      scripts: scripts,
      plans: plans,
      records: records,
    ),
  );
}

bool _shouldBuildSnapshotInBackground({
  required List<RecastExhibitionScript> recastScripts,
  required List<TokenizerScript> scripts,
  required List<ProductionPlan> plans,
  required List<StudioGalleryRecord> records,
}) {
  if (scripts.isEmpty &&
      plans.isEmpty &&
      records.isEmpty &&
      recastScripts.every((script) => script.summaryOnly)) {
    return false;
  }
  var workItems = records.length;
  for (final script in recastScripts) {
    workItems += script.frames.length + script.imageAttachments.length;
  }
  for (final script in scripts) {
    workItems += script.sourceFiles.length;
    workItems += script.imageTasks.length;
    workItems += script.imageAttachments.length;
  }
  for (final plan in plans) {
    workItems += plan.tasks.length;
  }
  return workItems >= _backgroundSnapshotWorkItemThreshold;
}

const _backgroundSnapshotWorkItemThreshold = 32;

ScriptExhibitionSnapshot _buildSnapshotFromRequest(
  _ScriptExhibitionSnapshotRequest request,
) {
  return _buildSnapshot(
    recastScripts: request.recastScripts,
    scripts: request.scripts,
    plans: request.plans,
    records: request.records,
  );
}

class _ScriptExhibitionSnapshotRequest {
  final List<RecastExhibitionScript> recastScripts;
  final List<TokenizerScript> scripts;
  final List<ProductionPlan> plans;
  final List<StudioGalleryRecord> records;

  const _ScriptExhibitionSnapshotRequest({
    required this.recastScripts,
    required this.scripts,
    required this.plans,
    required this.records,
  });
}

String _recastSourceVersionLabel(RecastExhibitionScript script) {
  return script.isImageOnly ? '默认版本' : '原始剧本';
}

String _recastSourceVersionDescription(RecastExhibitionScript script) {
  return script.isImageOnly ? '导入时保留的默认图片版本。' : '导入时保留的原始剧本帧。';
}

String _imagePathForRecastFrame(
  RecastExhibitionFrame frame, {
  required _ImagePathsByLeafProvider imagePathsByLeaf,
}) {
  return _firstNonEmpty([
        _existingLocalImagePath(frame.sourceImagePath),
        _isImagePath(frame.sourcePath)
            ? _existingLocalImagePath(frame.sourcePath)
            : null,
        _sidecarImagePath(
          sourcePath: frame.sourcePath,
          fileName: frame.fileName,
          imagePathsByLeaf: imagePathsByLeaf,
        ),
      ]) ??
      '';
}

String _knownImagePathForRecastFrame(RecastExhibitionFrame frame) {
  return _firstNonEmpty([
        _existingLocalImagePath(frame.sourceImagePath),
        _isImagePath(frame.sourcePath)
            ? _existingLocalImagePath(frame.sourcePath)
            : null,
      ]) ??
      '';
}

String? _existingLocalImagePath(String? path) {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty || !_isImagePath(trimmed)) {
    return null;
  }
  return File(trimmed).existsSync() ? trimmed : null;
}

String _recastFrameStatusLabel(ScriptFrameParseStatus status) {
  return switch (status) {
    ScriptFrameParseStatus.parsed => '已解析',
    ScriptFrameParseStatus.error => '解析失败',
  };
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return _imageExtensions.any(lower.endsWith);
}

const _imageExtensions = ['.png', '.jpg', '.jpeg', '.webp'];

bool _isLocalImageReference(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return false;
  }
  return _isImagePath(trimmed);
}

bool _isLocalImagePath(String path) {
  final trimmed = path.trim();
  return _isLocalImageReference(trimmed) && File(trimmed).existsSync();
}

Future<ScriptExhibitionSourceFolderCleanupPreview> _previewSourceFolderCleanup(
  ScriptExhibitionScript script,
) async {
  final sourceFolder = script.sourceFolder.trim();
  if (sourceFolder.isEmpty) {
    return const ScriptExhibitionSourceFolderCleanupPreview(
      sourceFolder: '',
      sourceFolderExists: false,
    );
  }
  final directory = Directory(sourceFolder);
  if (!await directory.exists()) {
    return ScriptExhibitionSourceFolderCleanupPreview(
      sourceFolder: sourceFolder,
      sourceFolderExists: false,
    );
  }
  final sourceImages = await _listSourceFolderImagePaths(directory);
  final retainedImages = _referencedSourceFolderImagePaths(
    script,
    sourceFolder: directory.path,
  );
  final retainedKeys = {
    for (final path in retainedImages) _normalizedFilePathKey(path),
  };
  final removableImages = [
    for (final path in sourceImages)
      if (!retainedKeys.contains(_normalizedFilePathKey(path))) path,
  ];
  return ScriptExhibitionSourceFolderCleanupPreview(
    sourceFolder: directory.path,
    sourceFolderExists: true,
    sourceImagePaths: List.unmodifiable(sourceImages),
    retainedImagePaths: List.unmodifiable(retainedImages),
    removableImagePaths: List.unmodifiable(removableImages),
  );
}

Future<List<String>> _listSourceFolderImagePaths(Directory directory) async {
  final paths = <String>[];
  try {
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File || !_isImagePath(entity.path)) {
        continue;
      }
      paths.add(entity.absolute.path);
    }
  } on FileSystemException {
    return const [];
  }
  paths.sort(_compareNormalizedPaths);
  return paths;
}

List<String> _referencedSourceFolderImagePaths(
  ScriptExhibitionScript script, {
  required String sourceFolder,
}) {
  final pathsByKey = <String, String>{};
  void add(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        !_isImagePath(trimmed) ||
        !_pathIsInsideDirectory(trimmed, sourceFolder)) {
      return;
    }
    pathsByKey.putIfAbsent(_normalizedFilePathKey(trimmed), () => trimmed);
  }

  for (final item in script.items) {
    add(item.imagePath);
    add(item.sourcePath);
    add(item.galleryRecord?.imagePath);
    add(item.galleryRecord?.provenance?.outputImagePath);
  }
  final paths = pathsByKey.values.toList(growable: false)
    ..sort(_compareNormalizedPaths);
  return paths;
}

bool _pathIsInsideDirectory(String path, String directoryPath) {
  final pathKey = _normalizedFilePathKey(path);
  final directoryKey = _normalizedDirectoryPathKey(directoryPath);
  return pathKey == directoryKey || pathKey.startsWith('$directoryKey/');
}

int _compareNormalizedPaths(String left, String right) =>
    _normalizedFilePathKey(left).compareTo(_normalizedFilePathKey(right));

String _normalizedFilePathKey(String path) =>
    _normalizedPathKey(File(path).absolute.path);

String _normalizedDirectoryPathKey(String path) =>
    _normalizedPathKey(Directory(path).absolute.path);

String _normalizedPathKey(String path) {
  final normalized =
      path.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

Map<String, dynamic> _knownGenerationParamsForItem(
  ScriptExhibitionItem item,
) {
  if (item.generationParams.isNotEmpty) {
    return item.generationParams;
  }
  final recordParamConfig = _mapValue(
    item.galleryRecord?.document.payload['param_config'],
  );
  if (recordParamConfig.isNotEmpty) {
    return _lightweightProductionParameters(recordParamConfig);
  }
  final lineageParams = _lightweightProductionParameters(
    item.galleryRecord?.lineage?.parameters,
  );
  if (lineageParams.isNotEmpty) {
    return lineageParams;
  }
  return _lightweightProductionParameters(
      item.assetCapturePayload?['parameters']);
}

bool _hasDisplayedGenerationParams(Map<String, dynamic> params) {
  for (final key in const [
    'seed',
    'steps',
    'sampler',
    'scale',
    'cfg_rescale',
    'noise_schedule',
  ]) {
    if (_hasGenerationParamValue(params[key])) {
      return true;
    }
  }
  return _hasGenerationParamValue(params['width']) &&
      _hasGenerationParamValue(params['height']);
}

bool _hasGenerationParamValue(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is String) {
    return value.trim().isNotEmpty;
  }
  return value is num || value is bool;
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

Future<Map<String, dynamic>> _loadImageGenerationParamsFromMetadata(
  String imagePath,
) async {
  final file = File(imagePath);
  try {
    if (!await file.exists()) {
      return const <String, dynamic>{};
    }
    final parsed = await WorkbenchMetadataImportService().parseFile(file);
    final params = <String, dynamic>{...parsed.parameters};
    if (parsed.width != null) {
      params.putIfAbsent('width', () => parsed.width);
    }
    if (parsed.height != null) {
      params.putIfAbsent('height', () => parsed.height);
    }
    return _lightweightProductionParameters(params);
  } catch (_) {
    return const <String, dynamic>{};
  }
}

typedef _ImagePathsByLeafProvider = Map<String, String> Function();

Map<String, String> _imagePathsByLeaf(String rootPath) {
  final directory = Directory(rootPath);
  if (!directory.existsSync()) {
    return const {};
  }
  try {
    final files = directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => _isImagePath(file.path))
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    return {
      for (final file in files)
        _fileNameFromPath(file.path).toLowerCase(): file.path,
    };
  } on FileSystemException {
    return const {};
  }
}

String? _sidecarImagePath({
  required String? sourcePath,
  required String? fileName,
  required _ImagePathsByLeafProvider imagePathsByLeaf,
}) {
  final existingSibling = _existingSiblingImagePath(sourcePath);
  if (existingSibling != null) {
    return existingSibling;
  }
  final stem = _fileStem(_firstNonEmpty([sourcePath, fileName]) ?? '');
  if (stem.isEmpty) {
    return null;
  }
  final pathsByLeaf = imagePathsByLeaf();
  for (final extension in _imageExtensions) {
    final match = pathsByLeaf['$stem$extension'];
    if (match != null) {
      return match;
    }
  }
  return null;
}

String? _existingSiblingImagePath(String? sourcePath) {
  final trimmed = sourcePath?.trim();
  if (trimmed == null || trimmed.isEmpty || _isImagePath(trimmed)) {
    return null;
  }
  final lastForwardSlash = trimmed.lastIndexOf('/');
  final lastBackslash = trimmed.lastIndexOf('\\');
  final lastSeparator =
      lastForwardSlash > lastBackslash ? lastForwardSlash : lastBackslash;
  final dot = trimmed.lastIndexOf('.');
  if (dot <= lastSeparator) {
    return null;
  }
  final prefix = trimmed.substring(0, dot);
  for (final extension in _imageExtensions) {
    final candidate = '$prefix$extension';
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

class _MutableScriptBucket {
  final String scriptId;
  String title;
  String sourceFolder;
  DateTime updatedAt;
  final Map<String, _MutableVersionBucket> versions = {};
  final Set<String> categoryNames = {};
  final Map<String, String> versionLabelOverrides = {};
  String? coverItemId;
  int syntheticOriginalImageCount = 0;
  bool summaryOnly = false;

  _MutableScriptBucket({
    required this.scriptId,
    required this.title,
    required this.sourceFolder,
    required this.updatedAt,
  });

  void merge({
    String? title,
    String? sourceFolder,
    DateTime? updatedAt,
  }) {
    final nextTitle = title?.trim();
    if (nextTitle != null && nextTitle.isNotEmpty) {
      this.title = nextTitle;
    }
    final nextFolder = sourceFolder?.trim();
    if (nextFolder != null && nextFolder.isNotEmpty) {
      this.sourceFolder = nextFolder;
    }
    if (updatedAt != null && updatedAt.isAfter(this.updatedAt)) {
      this.updatedAt = updatedAt;
    }
  }

  void markSummaryOnly() {
    summaryOnly = true;
  }

  void addSyntheticOriginalImageCount(int count) {
    if (count <= 0) return;
    syntheticOriginalImageCount += count;
  }

  void mergeCategories(List<String> names) {
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) {
        categoryNames.add(trimmed);
      }
    }
  }

  void mergeVersionLabels(Map<String, String> labels) {
    for (final entry in labels.entries) {
      final versionId = entry.key.trim();
      final label = entry.value.trim();
      if (versionId.isNotEmpty && label.isNotEmpty) {
        versionLabelOverrides[versionId] = label;
      }
    }
  }

  void mergeCoverItemId(String? itemId) {
    final trimmed = itemId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      coverItemId = trimmed;
    }
  }

  void addItem(
    ScriptExhibitionItem item, {
    required String versionDescription,
    required DateTime versionUpdatedAt,
  }) {
    final itemLabel =
        versionLabelOverrides[item.versionId] ?? item.versionLabel;
    final labeledItem = itemLabel == item.versionLabel
        ? item
        : item.copyWith(versionLabel: itemLabel);
    final bucket = versions.putIfAbsent(
      item.versionId,
      () => _MutableVersionBucket(
        id: item.versionId,
        label: itemLabel,
        description: versionDescription,
        updatedAt: versionUpdatedAt,
      ),
    );
    bucket.add(labeledItem, updatedAt: versionUpdatedAt);
  }

  ScriptExhibitionScript toScript() {
    final versionsOut = versions.values
        .map(
          (version) => version.toVersion(
            labelOverride: versionLabelOverrides[version.id],
          ),
        )
        .toList()
      ..sort(_compareVersions);
    var originalCount = syntheticOriginalImageCount;
    var generatedCount = 0;
    var imageLikeCount = syntheticOriginalImageCount;
    var pendingCount = 0;
    var hasImage = false;
    ScriptExhibitionItem? savedCover;
    ScriptExhibitionItem? generatedCover;
    ScriptExhibitionItem? attachmentCover;
    ScriptExhibitionItem? originalCover;
    ScriptExhibitionItem? fallbackCover;
    ScriptExhibitionItem? firstNeedsActionOutsideOriginal;
    ScriptExhibitionItem? firstNeedsAction;
    final savedCoverId = coverItemId?.trim();
    for (final version in versionsOut) {
      if (version.id == ScriptExhibitionVersion.originalId) {
        originalCount += version.items.length;
      }
      for (final item in version.items) {
        if (item.sourceKind != ScriptExhibitionItemSourceKind.failed) {
          imageLikeCount += 1;
        }
        final itemHasImage = item.hasImage;
        if (itemHasImage) {
          hasImage = true;
          fallbackCover ??= item;
          if (savedCoverId != null &&
              savedCoverId.isNotEmpty &&
              item.id == savedCoverId) {
            savedCover ??= item;
          }
          switch (item.sourceKind) {
            case ScriptExhibitionItemSourceKind.generated:
            case ScriptExhibitionItemSourceKind.gallery:
              generatedCover ??= item;
              generatedCount += 1;
            case ScriptExhibitionItemSourceKind.attachment:
              attachmentCover ??= item;
            case ScriptExhibitionItemSourceKind.original:
              originalCover ??= item;
            case ScriptExhibitionItemSourceKind.queued:
            case ScriptExhibitionItemSourceKind.failed:
              break;
          }
        }
        if (item.needsAction) {
          pendingCount += 1;
          firstNeedsAction ??= item;
          if (version.id != ScriptExhibitionVersion.originalId) {
            firstNeedsActionOutsideOriginal ??= item;
          }
        }
      }
    }
    final coverItem = savedCover ??
        generatedCover ??
        attachmentCover ??
        originalCover ??
        fallbackCover;
    final status = pendingCount > 0
        ? ScriptExhibitionScriptStatus.needsAction
        : generatedCount > 0
            ? ScriptExhibitionScriptStatus.archived
            : ScriptExhibitionScriptStatus.active;
    return ScriptExhibitionScript(
      scriptId: scriptId,
      title: title,
      sourceFolder: sourceFolder,
      updatedAt: updatedAt,
      versions: List.unmodifiable(versionsOut),
      status: status,
      categoryNames: List.unmodifiable(categoryNames),
      coverItemId: coverItemId,
      originalCount: originalCount,
      generatedImageCount: generatedCount,
      imageLikeItemCount: imageLikeCount,
      hasImage: hasImage,
      coverItem: coverItem,
      pendingCount: pendingCount,
      firstNeedsActionItem: firstNeedsActionOutsideOriginal ?? firstNeedsAction,
      summaryOnly: summaryOnly,
      searchText: _scriptSearchTextFromValues(
        scriptId: scriptId,
        title: title,
        sourceFolder: sourceFolder,
        categoryNames: List.unmodifiable(categoryNames),
        versions: List.unmodifiable(versionsOut),
      ),
    );
  }
}

class _MutableVersionBucket {
  final String id;
  final String label;
  final String description;
  DateTime updatedAt;
  final List<ScriptExhibitionItem> items = [];

  _MutableVersionBucket({
    required this.id,
    required this.label,
    required this.description,
    required this.updatedAt,
  });

  void add(ScriptExhibitionItem item, {required DateTime updatedAt}) {
    items.add(item);
    if (updatedAt.isAfter(this.updatedAt)) {
      this.updatedAt = updatedAt;
    }
  }

  ScriptExhibitionVersion toVersion({String? labelOverride}) {
    final displayLabel = labelOverride?.trim().isNotEmpty == true
        ? labelOverride!.trim()
        : label;
    final sortedItems = [...items]..sort(_compareItems);
    return ScriptExhibitionVersion(
      id: id,
      label: displayLabel,
      description: description,
      updatedAt: updatedAt,
      items: List.unmodifiable([
        for (final item in sortedItems)
          item.versionLabel == displayLabel
              ? item
              : item.copyWith(versionLabel: displayLabel),
      ]),
    );
  }
}

int _compareVersions(
  ScriptExhibitionVersion left,
  ScriptExhibitionVersion right,
) {
  int rank(ScriptExhibitionVersion version) {
    if (version.id == ScriptExhibitionVersion.originalId) return 0;
    if (version.id == ScriptExhibitionVersion.galleryId) return 3;
    return 2;
  }

  final rankCompare = rank(left).compareTo(rank(right));
  if (rankCompare != 0) return rankCompare;
  return right.updatedAt.compareTo(left.updatedAt);
}

int _compareItems(ScriptExhibitionItem left, ScriptExhibitionItem right) {
  final leftFrame = left.frameIndex ?? 1 << 30;
  final rightFrame = right.frameIndex ?? 1 << 30;
  final frameCompare = leftFrame.compareTo(rightFrame);
  if (frameCompare != 0) return frameCompare;
  final updatedCompare = left.updatedAt.compareTo(right.updatedAt);
  if (updatedCompare != 0) return updatedCompare;
  return left.id.compareTo(right.id);
}

int _compareScriptsForSort(
  ScriptExhibitionScript left,
  ScriptExhibitionScript right,
  ScriptExhibitionScriptSort sort,
) {
  final primary = switch (sort) {
    ScriptExhibitionScriptSort.recent =>
      right.updatedAt.compareTo(left.updatedAt),
    ScriptExhibitionScriptSort.title => _compareText(left.title, right.title),
    ScriptExhibitionScriptSort.imageCount =>
      right.originalCount.compareTo(left.originalCount),
    ScriptExhibitionScriptSort.needsAction =>
      right.pendingCount.compareTo(left.pendingCount),
  };
  if (primary != 0) return primary;
  final recentCompare = right.updatedAt.compareTo(left.updatedAt);
  if (recentCompare != 0) return recentCompare;
  final titleCompare = _compareText(left.title, right.title);
  if (titleCompare != 0) return titleCompare;
  return left.scriptId.compareTo(right.scriptId);
}

int _compareItemsForSort(
  ScriptExhibitionItem left,
  ScriptExhibitionItem right,
  ScriptExhibitionItemSort sort,
) {
  final primary = switch (sort) {
    ScriptExhibitionItemSort.frame => _compareItems(left, right),
    ScriptExhibitionItemSort.recent =>
      right.updatedAt.compareTo(left.updatedAt),
    ScriptExhibitionItemSort.oldest =>
      left.updatedAt.compareTo(right.updatedAt),
  };
  if (primary != 0) return primary;
  return _compareItems(left, right);
}

int _compareText(String left, String right) {
  final normalizedLeft = left.trim().toLowerCase();
  final normalizedRight = right.trim().toLowerCase();
  final normalizedCompare = normalizedLeft.compareTo(normalizedRight);
  if (normalizedCompare != 0) return normalizedCompare;
  return left.compareTo(right);
}

_MutableScriptBucket? _findStrongScriptBucket({
  required String? scriptId,
  required String? sourceFolder,
  required Map<String, _MutableScriptBucket> bucketsByStrongAlias,
}) {
  for (final alias in _scriptStrongAliases(
    scriptId: scriptId,
    sourceFolder: sourceFolder,
  )) {
    final bucket = bucketsByStrongAlias[alias];
    if (bucket != null) return bucket;
  }
  return null;
}

_MutableScriptBucket? _findWeakScriptBucket({
  required String? title,
  required String? sourceFolder,
  required String? sourceFileName,
  required int? frameIndex,
  required Map<String, _MutableScriptBucket?> bucketsByTitleAlias,
}) {
  final titleAlias = _scriptTitleAlias(title);
  if (titleAlias == null) return null;
  final bucket = bucketsByTitleAlias[titleAlias];
  if (bucket == null) return null;
  if (!_hasText(sourceFolder)) return bucket;
  return _bucketHasSourceEvidence(
    bucket,
    sourceFileName: sourceFileName,
    frameIndex: frameIndex,
  )
      ? bucket
      : null;
}

bool _bucketHasSourceEvidence(
  _MutableScriptBucket bucket, {
  required String? sourceFileName,
  required int? frameIndex,
}) {
  final incomingFileAlias = _sourceFileAlias(sourceFileName);
  if (incomingFileAlias != null) {
    for (final version in bucket.versions.values) {
      for (final item in version.items) {
        if (_sourceFileAlias(item.sourceFileName) == incomingFileAlias ||
            _sourceFileAlias(item.sourcePath) == incomingFileAlias) {
          return true;
        }
      }
    }
    return false;
  }
  if (frameIndex == null) return false;
  for (final version in bucket.versions.values) {
    for (final item in version.items) {
      if (item.frameIndex == frameIndex) {
        return true;
      }
    }
  }
  return false;
}

String? _sourceFileAlias(String? value) {
  final normalized = value?.trim().replaceAll('\\', '/');
  if (normalized == null || normalized.isEmpty) return null;
  final leaf = normalized.split('/').last.trim();
  return leaf.isEmpty ? null : leaf.toLowerCase();
}

List<String> _scriptStrongAliases({
  required String? scriptId,
  required String? sourceFolder,
}) {
  return [
    if (_scriptIdAlias(scriptId) case final alias?) alias,
    if (_sourceFolderAlias(sourceFolder) case final alias?) alias,
  ];
}

String? _scriptIdAlias(String? scriptId) =>
    _identityAlias('id', scriptId?.trim());

String? _sourceFolderAlias(String? sourceFolder) {
  final normalized = sourceFolder
      ?.trim()
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/+$'), '');
  return _identityAlias('path', normalized);
}

String? _scriptTitleAlias(String? title) {
  final normalized = title?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return _identityAlias('title', normalized);
}

String? _identityAlias(String prefix, String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return '$prefix:${trimmed.toLowerCase()}';
}

String _productionTaskProvenanceKey(String planId, String taskId) {
  return '${planId.trim().toLowerCase()}::${taskId.trim().toLowerCase()}';
}

Map<String, List<StudioGalleryRecord>> _galleryRecordsByProductionTaskKey(
  List<StudioGalleryRecord> records,
) {
  final result = <String, List<StudioGalleryRecord>>{};
  for (final record in records) {
    final provenance = record.provenance;
    if (provenance == null) continue;
    final key = _productionTaskProvenanceKey(
      provenance.productionPlanId,
      provenance.taskId,
    );
    result.putIfAbsent(key, () => []).add(record);
  }
  return result;
}

StudioGalleryRecord? _matchingGalleryRecordForTask({
  required String planId,
  required ProductionTask task,
  required Map<String, List<StudioGalleryRecord>> recordsByProductionTaskKey,
}) {
  final candidates =
      recordsByProductionTaskKey[_productionTaskProvenanceKey(planId, task.id)];
  if (candidates == null) return null;
  for (final record in candidates) {
    final provenance = record.provenance;
    if (provenance == null) continue;
    if (_matchesProductionTaskProvenance(task.source, provenance)) {
      return record;
    }
  }
  return null;
}

bool _matchesProductionTaskProvenance(
  ProductionTaskSource source,
  StudioRecastProvenance provenance,
) {
  final sourceAliases = _scriptStrongAliases(
    scriptId: source.scriptId,
    sourceFolder: source.scriptPath,
  ).toSet();
  final provenanceAliases = _scriptStrongAliases(
    scriptId: provenance.scriptId,
    sourceFolder: provenance.scriptPath,
  ).toSet();
  if (sourceAliases.isNotEmpty && provenanceAliases.isNotEmpty) {
    return sourceAliases.intersection(provenanceAliases).isNotEmpty;
  }

  final sourceTitle = _scriptTitleAlias(source.scriptName);
  final provenanceTitle = _scriptTitleAlias(provenance.scriptName);
  return sourceTitle != null && sourceTitle == provenanceTitle;
}

bool _hasText(String? value) => value?.trim().isNotEmpty == true;

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String _defaultImagePathForSource(
  TokenizerSourceFile sourceFile, {
  required _ImagePathsByLeafProvider imagePathsByLeaf,
}) {
  final defaultImagePath = sourceFile.defaultImagePath.trim();
  if (defaultImagePath.isNotEmpty) {
    return defaultImagePath;
  }
  if (sourceFile.kind == TokenizerScriptSourceKind.image) {
    return sourceFile.path;
  }
  return _sidecarImagePath(
        sourcePath: sourceFile.path,
        fileName: sourceFile.fileName,
        imagePathsByLeaf: imagePathsByLeaf,
      ) ??
      '';
}

String _sourceVersionLabel(TokenizerScript script) {
  return _isImageOnlyScript(script) ? '默认版本' : '原始剧本';
}

String _sourceVersionDescription(TokenizerScript script) {
  return _isImageOnlyScript(script) ? '导入时保留的默认图片版本。' : '导入时保留的原始剧本帧。';
}

String _attachmentVersionId(TokenizerScriptImageAttachment attachment) {
  final versionId = attachment.versionId.trim();
  return versionId;
}

String _attachmentVersionLabel(TokenizerScriptImageAttachment attachment) {
  final versionLabel = attachment.versionLabel.trim();
  return versionLabel.isEmpty ? '导入图片' : versionLabel;
}

bool _isImageOnlyScript(TokenizerScript script) {
  final sourceFiles = [
    ...script.sourceFiles,
    for (final task in script.imageTasks) task.sourceFile,
  ];
  if (sourceFiles.isEmpty) {
    return false;
  }
  return sourceFiles.every(
    (sourceFile) => sourceFile.kind == TokenizerScriptSourceKind.image,
  );
}

String _fallback(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}

String _frameTitle(int? frameIndex, String? sourceFileName) {
  final fileName = sourceFileName?.trim();
  final prefix =
      frameIndex == null ? '片段' : '#${frameIndex.toString().padLeft(2, '0')}';
  if (fileName == null || fileName.isEmpty) {
    return prefix;
  }
  return '$prefix $fileName';
}

String _tokenizerStatusLabel(TokenizerTaskReviewStatus status) {
  return switch (status) {
    TokenizerTaskReviewStatus.auto => '自动解析',
    TokenizerTaskReviewStatus.needsReview => '待确认',
    TokenizerTaskReviewStatus.confirmed => '已确认',
    TokenizerTaskReviewStatus.adjusted => '已调整',
    TokenizerTaskReviewStatus.failed => '解析失败',
  };
}

ScriptExhibitionItemSourceKind _productionKind(ProductionTaskStatus status) {
  return switch (status) {
    ProductionTaskStatus.completed => ScriptExhibitionItemSourceKind.generated,
    ProductionTaskStatus.failed => ScriptExhibitionItemSourceKind.failed,
    ProductionTaskStatus.queued ||
    ProductionTaskStatus.running ||
    ProductionTaskStatus.skipped =>
      ScriptExhibitionItemSourceKind.queued,
  };
}

String _productionStatusLabel(ProductionTask task) {
  return switch (task.status) {
    ProductionTaskStatus.queued => '待生成',
    ProductionTaskStatus.running => '生成中',
    ProductionTaskStatus.completed => '已生成',
    ProductionTaskStatus.failed =>
      '生成失败${task.error == null ? '' : ': ${task.error}'}',
    ProductionTaskStatus.skipped => '已跳过',
  };
}

String _payloadPrompt(Map<String, dynamic> payload) {
  final parameters = payload['parameters'];
  if (parameters is Map) {
    final promptRows = _v4PromptRowsFromPayloadParameters(parameters);
    if (promptRows.isNotEmpty) {
      return promptRows.join(', ');
    }
  }
  final input = payload['input'];
  if (input is String && input.trim().isNotEmpty) return input.trim();
  final prompt = payload['prompt'];
  if (prompt is String && prompt.trim().isNotEmpty) return prompt.trim();
  return '';
}

Map<String, dynamic>? _lightweightProductionPayload(
  Map<String, dynamic> payload,
) {
  final result = <String, dynamic>{};
  for (final key in const ['input', 'prompt', 'uc']) {
    final text = _nonEmptyString(payload[key]);
    if (text != null) {
      result[key] = text;
    }
  }

  final parameters = _lightweightProductionParameters(
    payload['parameters'] ?? payload['param_config'],
  );
  if (parameters.isNotEmpty) {
    result['parameters'] = parameters;
  }

  final promptConfig = payload['prompt_config'];
  if (promptConfig is Map) {
    result['prompt_config'] = Map.unmodifiable(
      promptConfig.cast<String, dynamic>(),
    );
  }
  final characterConfig = payload['character_config'];
  if (characterConfig is List) {
    result['character_config'] = List.unmodifiable(characterConfig);
  }
  final savedConfig = payload['saved_config'];
  if (savedConfig is List) {
    result['saved_config'] = List.unmodifiable(savedConfig);
  }

  return result.isEmpty ? null : Map.unmodifiable(result);
}

Map<String, dynamic> _lightweightProductionParameters(Object? value) {
  if (value is! Map) {
    return const <String, dynamic>{};
  }
  final parameters = value.cast<String, dynamic>();
  final result = <String, dynamic>{};
  for (final key in const [
    'v4_prompt',
    'v4_negative_prompt',
    'prompt',
    'uc',
    'negative_prompt',
    'seed',
    'steps',
    'sampler',
    'scale',
    'cfg_rescale',
    'width',
    'height',
    'noise_schedule',
  ]) {
    final entry = parameters[key];
    if (entry == null) {
      continue;
    }
    if (entry is String && entry.trim().isEmpty) {
      continue;
    }
    result[key] = entry;
  }
  return result.isEmpty ? const <String, dynamic>{} : Map.unmodifiable(result);
}

List<String> _v4PromptRowsFromPayloadParameters(Map<dynamic, dynamic> params) {
  final v4Prompt = params['v4_prompt'];
  if (v4Prompt is! Map) return const [];
  final captionJson = v4Prompt['caption'];
  if (captionJson is! Map) return const [];
  final rows = <String>[
    if (_nonEmptyString(captionJson['base_caption']) case final text?) text,
    if (_nonEmptyString(captionJson['baseCaption']) case final text?) text,
    if (_nonEmptyString(captionJson['prompt']) case final text?) text,
  ];
  final charCaptions = captionJson['char_captions'];
  if (charCaptions is List) {
    for (final entry in charCaptions) {
      if (entry is! Map) continue;
      if (_nonEmptyString(entry['char_caption']) case final text?) {
        rows.add(text);
      }
    }
  }
  return List.unmodifiable(rows);
}

String? _nonEmptyString(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  String two(int input) => input.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _fileNameFromPath(String path) {
  return path.replaceAll('\\', '/').split('/').last;
}

String _fileStem(String path) {
  final fileName = _fileNameFromPath(path).trim();
  final dot = fileName.lastIndexOf('.');
  return dot <= 0
      ? fileName.toLowerCase()
      : fileName.substring(0, dot).toLowerCase();
}
