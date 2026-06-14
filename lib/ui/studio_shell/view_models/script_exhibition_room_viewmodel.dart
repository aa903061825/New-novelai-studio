import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/models/script_recast_knowledge.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';

typedef ScriptExhibitionScriptsLoader = Future<List<TokenizerScript>>
    Function();
typedef ScriptExhibitionRecastCachesLoader = Future<List<RecastScriptCache>>
    Function();
typedef ScriptExhibitionProductionPlansLoader = Future<List<ProductionPlan>>
    Function();
typedef ScriptExhibitionGalleryRecordsLoader = Future<List<StudioGalleryRecord>>
    Function();
typedef ScriptExhibitionScriptDeleter = Future<void> Function(
  ScriptExhibitionScript script, {
  bool deleteLocalFiles,
});
typedef ScriptExhibitionItemDeleter = Future<void> Function(
  ScriptExhibitionItem item,
);
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
typedef ScriptExhibitionItemCoverSetter = Future<void> Function(
  ScriptExhibitionItem item,
);

Future<List<TokenizerScript>> _loadNoTokenizerScripts() async => const [];

Future<List<RecastScriptCache>> _loadNoRecastCaches() async => const [];

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
}

class ScriptExhibitionSnapshot {
  static const empty = ScriptExhibitionSnapshot(scripts: []);

  final List<ScriptExhibitionScript> scripts;

  const ScriptExhibitionSnapshot({required this.scripts});

  int get totalScriptCount => scripts.length;

  int get totalImageCount => scripts.fold(
        0,
        (total, script) => total + script.imageLikeItemCount,
      );

  int get generatedImageCount => scripts.fold(
        0,
        (total, script) => total + script.generatedImageCount,
      );

  int get needsActionCount => scripts
      .where(
          (script) => script.status == ScriptExhibitionScriptStatus.needsAction)
      .length;
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

class ScriptExhibitionScript {
  final String scriptId;
  final String title;
  final String sourceFolder;
  final DateTime updatedAt;
  final List<ScriptExhibitionVersion> versions;
  final ScriptExhibitionScriptStatus status;
  final List<String> categoryNames;
  final String? coverItemId;

  const ScriptExhibitionScript({
    required this.scriptId,
    required this.title,
    required this.sourceFolder,
    required this.updatedAt,
    required this.versions,
    required this.status,
    this.categoryNames = const [],
    this.coverItemId,
  });

  List<ScriptExhibitionItem> get items => [
        for (final version in versions) ...version.items,
      ];

  int get originalCount => versions
      .where((version) => version.id == ScriptExhibitionVersion.originalId)
      .fold(0, (total, version) => total + version.items.length);

  int get generatedImageCount => items
      .where((item) =>
          item.sourceKind == ScriptExhibitionItemSourceKind.generated ||
          item.sourceKind == ScriptExhibitionItemSourceKind.gallery)
      .where((item) => item.imagePath.trim().isNotEmpty)
      .length;

  int get imageLikeItemCount => items
      .where((item) => item.sourceKind != ScriptExhibitionItemSourceKind.failed)
      .length;

  bool get hasImage => items.any((item) => item.hasImage);

  ScriptExhibitionItem? get coverItem {
    final imageItems = [
      for (final item in items)
        if (item.hasImage) item,
    ];
    if (imageItems.isEmpty) return null;
    final coverId = coverItemId?.trim();
    if (coverId != null && coverId.isNotEmpty) {
      final savedCover =
          imageItems.where((item) => item.id == coverId).firstOrNull;
      if (savedCover != null) return savedCover;
    }

    ScriptExhibitionItem? firstWithKind(
      Set<ScriptExhibitionItemSourceKind> kinds,
    ) {
      for (final item in imageItems) {
        if (kinds.contains(item.sourceKind)) {
          return item;
        }
      }
      return null;
    }

    return firstWithKind({
          ScriptExhibitionItemSourceKind.generated,
          ScriptExhibitionItemSourceKind.gallery,
        }) ??
        firstWithKind({ScriptExhibitionItemSourceKind.attachment}) ??
        firstWithKind({ScriptExhibitionItemSourceKind.original}) ??
        imageItems.first;
  }

  int get pendingCount => items.where((item) => item.needsAction).length;

  ScriptExhibitionItem? get firstNeedsActionItem {
    for (final version in versions) {
      if (version.id == ScriptExhibitionVersion.originalId) {
        continue;
      }
      for (final item in version.items) {
        if (item.needsAction) return item;
      }
    }
    for (final version in versions) {
      for (final item in version.items) {
        if (item.needsAction) return item;
      }
    }
    return null;
  }

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
  static const activeCategoryId = 'active';
  static const archivedCategoryId = 'archived';
  static const needsActionCategoryId = 'needs-action';
  static const allDetailFilterId = 'detail-all';
  static const completedDetailFilterId = 'detail-completed';
  static const needsActionDetailFilterId = 'detail-needs-action';

  final ScriptExhibitionScriptsLoader loadScripts;
  final ScriptExhibitionRecastCachesLoader loadRecastCaches;
  final ScriptExhibitionProductionPlansLoader loadProductionPlans;
  final ScriptExhibitionGalleryRecordsLoader loadGalleryRecords;
  final ScriptExhibitionScriptImporter? importScriptFolder;
  final ScriptExhibitionScriptImageImporter? importScriptImages;
  final ScriptExhibitionScriptDeleter? deleteScriptRecord;
  final ScriptExhibitionItemDeleter? deleteItemRecord;
  final ScriptExhibitionScriptRenamer? renameScriptRecord;
  final ScriptExhibitionScriptCategoryAssigner? assignScriptCategory;
  final ScriptExhibitionCategoryDeleter? deleteCategoryRecord;
  final ScriptExhibitionImageAttachmentRenamer? renameImageAttachment;
  final ScriptExhibitionVersionLabelRenamer? renameVersionLabelRecord;
  final ScriptExhibitionItemCoverSetter? setCoverItemRecord;
  final List<ScriptExhibitionUserCategory> customCategories;
  final Map<String, List<String>> customCategoryScriptIds;
  final List<ScriptExhibitionUserCategory> _sessionCategories = [];
  final Set<String> _selectedScriptIds = {};

  ScriptExhibitionSnapshot snapshot = ScriptExhibitionSnapshot.empty;
  bool isLoading = false;
  Object? loadError;
  String selectedCategoryId = allCategoryId;
  String? selectedScriptId;
  String? selectedVersionId;
  String selectedDetailFilterId = allDetailFilterId;
  ScriptExhibitionScriptSort scriptSort = ScriptExhibitionScriptSort.recent;
  ScriptExhibitionItemSort itemSort = ScriptExhibitionItemSort.frame;
  String? focusedItemId;
  int _loadGeneration = 0;
  bool _hasLoaded = false;

  ScriptExhibitionRoomViewModel({
    ScriptExhibitionScriptsLoader? loadScripts,
    ScriptExhibitionRecastCachesLoader? loadRecastCaches,
    required this.loadProductionPlans,
    required this.loadGalleryRecords,
    this.importScriptFolder,
    this.importScriptImages,
    this.deleteScriptRecord,
    this.deleteItemRecord,
    this.renameScriptRecord,
    this.assignScriptCategory,
    this.deleteCategoryRecord,
    this.renameImageAttachment,
    ScriptExhibitionVersionLabelRenamer? renameVersionLabel,
    this.setCoverItemRecord,
    this.customCategories = const [],
    this.customCategoryScriptIds = const {},
  })  : loadScripts = loadScripts ?? _loadNoTokenizerScripts,
        loadRecastCaches = loadRecastCaches ?? _loadNoRecastCaches,
        renameVersionLabelRecord = renameVersionLabel;

  bool get canImportScripts => importScriptFolder != null;

  bool get canImportScriptImages => importScriptImages != null;

  bool get canDeleteScripts => deleteScriptRecord != null;

  bool get canDeleteItems => deleteItemRecord != null;

  bool get canRenameScripts => renameScriptRecord != null;

  bool get canCategorizeScripts => assignScriptCategory != null;

  bool get canDeleteCategories => deleteCategoryRecord != null;

  Set<String> get selectedScriptIds => Set.unmodifiable(_selectedScriptIds);

  bool get canRenameItems => renameImageAttachment != null;

  bool get canRenameVersions => renameVersionLabelRecord != null;

  bool get canSetCoverItems => setCoverItemRecord != null;

  List<ScriptExhibitionCategory> get categories => [
        ScriptExhibitionCategory(
          id: allCategoryId,
          title: '全部馆区',
          description: '所有剧本、原始帧和批量结果统一浏览。',
          count: snapshot.totalScriptCount,
          tags: const ['剧本', '原图', '新图'],
        ),
        for (final category in customCategories)
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
      ];

  List<ScriptExhibitionScript> get visibleScripts {
    final scripts = <ScriptExhibitionScript>[];
    if (selectedCategoryId != allCategoryId) {
      final categoryName = _customCategoryNameFromId(selectedCategoryId);
      if (categoryName != null) {
        scripts.addAll(
          snapshot.scripts.where(
            (script) => script.categoryNames.any(
              (name) => name.trim().toLowerCase() == categoryName,
            ),
          ),
        );
        return _sortVisibleScripts(scripts);
      }
      final assignedIds = customCategoryScriptIds[selectedCategoryId];
      if (assignedIds != null) {
        final assigned = assignedIds.toSet();
        scripts.addAll(
          snapshot.scripts
              .where((script) => assigned.contains(script.scriptId)),
        );
        return _sortVisibleScripts(scripts);
      }
    }
    scripts.addAll(
      snapshot.scripts.where((script) {
        return switch (selectedCategoryId) {
          allCategoryId => true,
          activeCategoryId =>
            script.status == ScriptExhibitionScriptStatus.active,
          archivedCategoryId =>
            script.status == ScriptExhibitionScriptStatus.archived,
          needsActionCategoryId =>
            script.status == ScriptExhibitionScriptStatus.needsAction,
          _ => true,
        };
      }),
    );
    return _sortVisibleScripts(scripts);
  }

  ScriptExhibitionItem? get focusedItem {
    final itemId = focusedItemId;
    if (itemId == null) return null;
    for (final script in snapshot.scripts) {
      for (final version in script.versions) {
        for (final item in version.items) {
          if (item.id == itemId) return item;
        }
      }
    }
    return null;
  }

  ScriptExhibitionScript? get selectedScript {
    final id = selectedScriptId;
    if (id == null) return null;
    return snapshot.scripts
        .where((script) => script.scriptId == id)
        .firstOrNull;
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

  List<ScriptExhibitionScript> get selectedShelfScripts {
    if (_selectedScriptIds.isEmpty) return const [];
    final selectedIds = _selectedScriptIds.toSet();
    return snapshot.scripts
        .where((script) => selectedIds.contains(script.scriptId))
        .toList(growable: false);
  }

  List<ScriptExhibitionScript> _sortVisibleScripts(
    List<ScriptExhibitionScript> scripts,
  ) {
    if (scriptSort == ScriptExhibitionScriptSort.recent) {
      return scripts;
    }
    return scripts
      ..sort((left, right) => _compareScriptsForSort(left, right, scriptSort));
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
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      final galleryRecords = () async {
        try {
          return await loadGalleryRecords();
        } catch (_) {
          return const <StudioGalleryRecord>[];
        }
      }();
      final results = await Future.wait<Object>([
        loadRecastCaches(),
        loadScripts(),
        loadProductionPlans(),
        galleryRecords,
      ]);
      final caches = results[0] as List<RecastScriptCache>;
      final scripts = results[1] as List<TokenizerScript>;
      final plans = results[2] as List<ProductionPlan>;
      final records = results[3] as List<StudioGalleryRecord>;
      if (generation != _loadGeneration) {
        return;
      }
      snapshot = _buildSnapshot(
        caches: caches,
        scripts: scripts,
        plans: plans,
        records: records,
      );
      _normalizeSelection();
    } catch (error) {
      if (generation != _loadGeneration) {
        return;
      }
      loadError = error;
    } finally {
      if (generation == _loadGeneration) {
        _hasLoaded = true;
        isLoading = false;
        notifyListeners();
      }
    }
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
    notifyListeners();
  }

  void selectScript(String scriptId) {
    selectedScriptId = scriptId;
    selectedVersionId = selectedScript?.versions.firstOrNull?.id;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    _selectedScriptIds.clear();
    notifyListeners();
  }

  void clearScriptSelection() {
    selectedScriptId = null;
    selectedVersionId = null;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    _selectedScriptIds.clear();
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

  void selectVersion(String versionId) {
    selectedVersionId = versionId;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
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
    }
    await load();
  }

  Future<void> deleteItem(ScriptExhibitionItem item) async {
    final deleter = deleteItemRecord;
    if (deleter == null || !item.canDelete) return;
    await deleter(item);
    await load();
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
    final assigner = assignScriptCategory;
    final normalized = categoryName.trim();
    if (assigner == null || normalized.isEmpty) return;
    final uniqueScripts = <String, ScriptExhibitionScript>{};
    for (final script in scripts) {
      uniqueScripts[script.scriptId] = script;
    }
    if (uniqueScripts.isEmpty) return;
    _ensureSessionCategory(normalized);
    for (final script in uniqueScripts.values) {
      await assigner(script, normalized);
    }
    await load();
    selectedCategoryId = _customCategoryId(normalized);
    selectedScriptId = null;
    selectedVersionId = null;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    _selectedScriptIds.clear();
    notifyListeners();
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
    await load();
  }

  Future<void> setCoverItem(ScriptExhibitionItem item) async {
    final setter = setCoverItemRecord;
    if (setter == null || !item.hasImage) return;
    await setter(item);
    await load();
    focusedItemId = item.id;
    notifyListeners();
  }

  void _normalizeSelection() {
    final scripts = snapshot.scripts;
    if (selectedScriptId != null &&
        !scripts.any((script) => script.scriptId == selectedScriptId)) {
      selectedScriptId = null;
      selectedVersionId = null;
      selectedDetailFilterId = allDetailFilterId;
      focusedItemId = null;
    }
    final script = selectedScript;
    if (script != null &&
        selectedVersionId != null &&
        !script.versions.any((version) => version.id == selectedVersionId)) {
      selectedVersionId = script.versions.firstOrNull?.id;
    }
    if (focusedItemId != null && focusedItem == null) {
      focusedItemId = null;
    }
    _selectedScriptIds.removeWhere(
      (scriptId) => !scripts.any((script) => script.scriptId == scriptId),
    );
    if (!detailFilters.any((filter) => filter.id == selectedDetailFilterId)) {
      selectedDetailFilterId = allDetailFilterId;
    }
  }

  List<ScriptExhibitionScript> _scriptsForCustomCategory(String categoryId) {
    final categoryName = _customCategoryNameFromId(categoryId);
    if (categoryName != null) {
      return snapshot.scripts
          .where(
            (script) => script.categoryNames.any(
              (name) => name.trim().toLowerCase() == categoryName,
            ),
          )
          .toList(growable: false);
    }
    final assignedIds = customCategoryScriptIds[categoryId];
    if (assignedIds == null) return const [];
    final assigned = assignedIds.toSet();
    return snapshot.scripts
        .where((script) => assigned.contains(script.scriptId))
        .toList(growable: false);
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
    for (final category in customCategories) {
      categoriesById.remove(category.id);
    }
    final categories = categoriesById.values.toList()
      ..sort((left, right) => left.title.compareTo(right.title));
    return categories;
  }

  void _ensureSessionCategory(String categoryName) {
    final normalized = categoryName.trim();
    final id = _customCategoryId(normalized);
    if (customCategories.any((category) => category.id == id) ||
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
  }
}

String _customCategoryId(String categoryName) =>
    'custom:${categoryName.trim()}';

bool _isProtectedCategoryId(String categoryId) {
  return switch (categoryId) {
    ScriptExhibitionRoomViewModel.allCategoryId ||
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

ScriptExhibitionSnapshot _buildSnapshot({
  required List<RecastScriptCache> caches,
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

  Map<String, String> imagePathsByLeafForRoot(String? rootPath) {
    final normalized = rootPath?.trim();
    if (normalized == null || normalized.isEmpty) {
      return const {};
    }
    return imagePathIndexesByRoot.putIfAbsent(
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

  for (final cache in caches) {
    final script = _scriptFromRecastCache(cache);
    if (script == null) {
      continue;
    }
    final scriptId = _firstNonEmpty([script.id, cache.scriptId]);
    final sourceFolder =
        _firstNonEmpty([script.rootPath, cache.sourceRootPath]);
    final bucket = bucketFor(
      scriptId: scriptId,
      title: _firstNonEmpty([script.name, cache.scriptName]),
      sourceFolder: sourceFolder,
      updatedAt: cache.updatedAt,
    );
    final imagePathsByLeaf = imagePathsByLeafForRoot(sourceFolder);
    bucket.mergeCategories(_legacyCategoryNamesFromRecastScript(script));
    bucket.mergeVersionLabels(_legacyVersionLabelsFromRecastScript(script));
    bucket.mergeCoverItemId(_legacyCoverItemIdFromRecastScript(script));
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
          subtitle: _recastFrameStatusLabel(frame),
          prompt: _promptFromRecastFrame(frame),
          imagePath: _imagePathForRecastFrame(
            frame,
            imagePathsByLeaf: imagePathsByLeaf,
          ),
          statusLabel: _recastFrameStatusLabel(frame),
          updatedAt: cache.updatedAt,
        ),
        versionDescription: sourceVersionDescription,
        versionUpdatedAt: cache.updatedAt,
      );
    }
    for (final attachment in _legacyImageAttachmentsFromRecastScript(script)) {
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

  return ScriptExhibitionSnapshot(scripts: List.unmodifiable(scriptsOut));
}

Script? _scriptFromRecastCache(RecastScriptCache cache) {
  if (cache.scriptSnapshot.isEmpty) {
    return null;
  }
  try {
    return Script.fromJson(cache.scriptSnapshot);
  } catch (_) {
    return null;
  }
}

List<String> _legacyCategoryNamesFromRecastScript(Script script) {
  final raw = script.meta['legacyCategoryNames'];
  if (raw is! List) {
    return const [];
  }
  return [
    for (final value in raw)
      if (value.toString().trim().isNotEmpty) value.toString(),
  ];
}

Map<String, String> _legacyVersionLabelsFromRecastScript(Script script) {
  final raw = script.meta['legacyExhibitionVersionLabels'];
  if (raw is! Map) {
    return const {};
  }
  return {
    for (final entry in raw.entries)
      if (entry.key.toString().trim().isNotEmpty &&
          entry.value.toString().trim().isNotEmpty)
        entry.key.toString(): entry.value.toString(),
  };
}

String? _legacyCoverItemIdFromRecastScript(Script script) {
  final text = script.meta['legacyExhibitionCoverItemId']?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<TokenizerScriptImageAttachment> _legacyImageAttachmentsFromRecastScript(
  Script script,
) {
  final raw = script.meta['legacyImageAttachments'];
  if (raw is! List) {
    return const [];
  }
  final attachments = <TokenizerScriptImageAttachment>[];
  for (final value in raw) {
    if (value is! Map) {
      continue;
    }
    try {
      attachments.add(
        TokenizerScriptImageAttachment.fromJson(value.cast<String, dynamic>()),
      );
    } catch (_) {
      // Ignore malformed legacy attachment records.
    }
  }
  return attachments;
}

String _recastSourceVersionLabel(Script script) {
  return _isImageOnlyRecastScript(script) ? '默认版本' : '原始剧本';
}

String _recastSourceVersionDescription(Script script) {
  return _isImageOnlyRecastScript(script) ? '导入时保留的默认图片版本。' : '导入时保留的原始剧本帧。';
}

bool _isImageOnlyRecastScript(Script script) {
  if (script.frames.isEmpty) {
    return false;
  }
  return script.frames.every((frame) => _isImagePath(frame.sourcePath));
}

String _promptFromRecastFrame(ScriptFrame frame) {
  final rows = [
    if (frame.parsed.baseCaption.trim().isNotEmpty)
      frame.parsed.baseCaption.trim(),
    for (final caption in frame.parsed.charCaptions)
      if (caption.trim().isNotEmpty) caption.trim(),
  ];
  return rows.join(', ');
}

String _imagePathForRecastFrame(
  ScriptFrame frame, {
  required Map<String, String> imagePathsByLeaf,
}) {
  return _firstNonEmpty([
        frame.sourceImagePath,
        _isImagePath(frame.sourcePath) ? frame.sourcePath : null,
        _sidecarImagePath(
          sourcePath: frame.sourcePath,
          fileName: frame.fileName,
          imagePathsByLeaf: imagePathsByLeaf,
        ),
      ]) ??
      '';
}

String _recastFrameStatusLabel(ScriptFrame frame) {
  return switch (frame.parseStatus) {
    ScriptFrameParseStatus.parsed => '已解析',
    ScriptFrameParseStatus.error => '解析失败',
  };
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return _imageExtensions.any(lower.endsWith);
}

const _imageExtensions = ['.png', '.jpg', '.jpeg', '.webp'];

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
  required Map<String, String> imagePathsByLeaf,
}) {
  final existingSibling = _existingSiblingImagePath(sourcePath);
  if (existingSibling != null) {
    return existingSibling;
  }
  final stem = _fileStem(_firstNonEmpty([sourcePath, fileName]) ?? '');
  if (stem.isEmpty) {
    return null;
  }
  for (final extension in _imageExtensions) {
    final match = imagePathsByLeaf['$stem$extension'];
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
    final hasNeedsAction = versionsOut
        .expand((version) => version.items)
        .any((item) => item.needsAction);
    final generatedCount = versionsOut
        .expand((version) => version.items)
        .where((item) =>
            item.sourceKind == ScriptExhibitionItemSourceKind.generated ||
            item.sourceKind == ScriptExhibitionItemSourceKind.gallery)
        .where((item) => item.imagePath.trim().isNotEmpty)
        .length;
    final status = hasNeedsAction
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
  return right.updatedAt.compareTo(left.updatedAt);
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
      right.imageLikeItemCount.compareTo(left.imageLikeItemCount),
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
  required Map<String, String> imagePathsByLeaf,
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
