import 'package:flutter/foundation.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';

typedef ScriptExhibitionScriptsLoader = Future<List<TokenizerScript>>
    Function();
typedef ScriptExhibitionProductionPlansLoader = Future<List<ProductionPlan>>
    Function();
typedef ScriptExhibitionGalleryRecordsLoader = Future<List<StudioGalleryRecord>>
    Function();
typedef ScriptExhibitionScriptDeleter = Future<void> Function(
  ScriptExhibitionScript script,
);
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
typedef ScriptExhibitionImageAttachmentRenamer = Future<void> Function(
  ScriptExhibitionItem item,
  String label,
);
typedef ScriptExhibitionVersionLabelRenamer = Future<void> Function(
  ScriptExhibitionScript script,
  ScriptExhibitionVersion version,
  String label,
);

enum ScriptExhibitionItemSourceKind {
  original,
  attachment,
  generated,
  queued,
  failed,
  gallery,
}

enum ScriptExhibitionScriptStatus { active, archived, needsAction }

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

  const ScriptExhibitionScript({
    required this.scriptId,
    required this.title,
    required this.sourceFolder,
    required this.updatedAt,
    required this.versions,
    required this.status,
    this.categoryNames = const [],
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
  static const attachmentsId = 'attachments';
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
  final ScriptExhibitionProductionPlansLoader loadProductionPlans;
  final ScriptExhibitionGalleryRecordsLoader loadGalleryRecords;
  final ScriptExhibitionScriptImporter? importScriptFolder;
  final ScriptExhibitionScriptImageImporter? importScriptImages;
  final ScriptExhibitionScriptDeleter? deleteScriptRecord;
  final ScriptExhibitionItemDeleter? deleteItemRecord;
  final ScriptExhibitionScriptRenamer? renameScriptRecord;
  final ScriptExhibitionScriptCategoryAssigner? assignScriptCategory;
  final ScriptExhibitionImageAttachmentRenamer? renameImageAttachment;
  final ScriptExhibitionVersionLabelRenamer? renameVersionLabelRecord;
  final List<ScriptExhibitionUserCategory> customCategories;
  final Map<String, List<String>> customCategoryScriptIds;
  final List<ScriptExhibitionUserCategory> _sessionCategories = [];

  ScriptExhibitionSnapshot snapshot = ScriptExhibitionSnapshot.empty;
  bool isLoading = false;
  Object? loadError;
  String selectedCategoryId = allCategoryId;
  String? selectedScriptId;
  String? selectedVersionId;
  String selectedDetailFilterId = allDetailFilterId;
  String? focusedItemId;
  int _loadGeneration = 0;

  ScriptExhibitionRoomViewModel({
    required this.loadScripts,
    required this.loadProductionPlans,
    required this.loadGalleryRecords,
    this.importScriptFolder,
    this.importScriptImages,
    this.deleteScriptRecord,
    this.deleteItemRecord,
    this.renameScriptRecord,
    this.assignScriptCategory,
    this.renameImageAttachment,
    ScriptExhibitionVersionLabelRenamer? renameVersionLabel,
    this.customCategories = const [],
    this.customCategoryScriptIds = const {},
  }) : renameVersionLabelRecord = renameVersionLabel;

  bool get canImportScripts => importScriptFolder != null;

  bool get canImportScriptImages => importScriptImages != null;

  bool get canDeleteScripts => deleteScriptRecord != null;

  bool get canDeleteItems => deleteItemRecord != null;

  bool get canRenameScripts => renameScriptRecord != null;

  bool get canCategorizeScripts => assignScriptCategory != null;

  bool get canRenameItems => renameImageAttachment != null;

  bool get canRenameVersions => renameVersionLabelRecord != null;

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
    if (selectedCategoryId != allCategoryId) {
      final categoryName = _customCategoryNameFromId(selectedCategoryId);
      if (categoryName != null) {
        return snapshot.scripts
            .where(
              (script) => script.categoryNames.any(
                (name) => name.trim().toLowerCase() == categoryName,
              ),
            )
            .toList(growable: false);
      }
      final assignedIds = customCategoryScriptIds[selectedCategoryId];
      if (assignedIds != null) {
        final assigned = assignedIds.toSet();
        return snapshot.scripts
            .where((script) => assigned.contains(script.scriptId))
            .toList(growable: false);
      }
    }
    return snapshot.scripts.where((script) {
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
    }).toList(growable: false);
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
    return switch (selectedDetailFilterId) {
      allDetailFilterId => items,
      completedDetailFilterId =>
        items.where((item) => !item.needsAction).toList(growable: false),
      needsActionDetailFilterId =>
        items.where((item) => item.needsAction).toList(growable: false),
      _ => items,
    };
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      final scripts = await loadScripts();
      final plans = await loadProductionPlans();
      List<StudioGalleryRecord> records;
      try {
        records = await loadGalleryRecords();
      } catch (_) {
        records = const [];
      }
      if (generation != _loadGeneration) {
        return;
      }
      snapshot = _buildSnapshot(
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
    await importer(script);
    await load();
  }

  void selectCategory(String categoryId) {
    if (selectedCategoryId == categoryId) return;
    selectedCategoryId = categoryId;
    selectedScriptId = null;
    selectedVersionId = null;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    notifyListeners();
  }

  void selectScript(String scriptId) {
    selectedScriptId = scriptId;
    selectedVersionId = selectedScript?.versions.firstOrNull?.id;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
    notifyListeners();
  }

  void clearScriptSelection() {
    selectedScriptId = null;
    selectedVersionId = null;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
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

  Future<void> deleteScript(ScriptExhibitionScript script) async {
    final deleter = deleteScriptRecord;
    if (deleter == null) return;
    await deleter(script);
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
    final assigner = assignScriptCategory;
    final normalized = categoryName.trim();
    if (assigner == null || normalized.isEmpty) return;
    _ensureSessionCategory(normalized);
    await assigner(script, normalized);
    await load();
    selectedCategoryId = _customCategoryId(normalized);
    selectedScriptId = null;
    selectedVersionId = null;
    selectedDetailFilterId = allDetailFilterId;
    focusedItemId = null;
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

String? _customCategoryNameFromId(String categoryId) {
  const prefix = 'custom:';
  if (!categoryId.startsWith(prefix)) return null;
  final value = categoryId.substring(prefix.length).trim().toLowerCase();
  return value.isEmpty ? null : value;
}

ScriptExhibitionSnapshot _buildSnapshot({
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
    DateTime? updatedAt,
  }) {
    final normalizedId = _firstNonEmpty([scriptId, sourceFolder, title]);
    if (normalizedId == null) {
      throw StateError('Script exhibition item is missing script identity.');
    }
    var bucket = _findScriptBucket(
      scriptId: scriptId,
      title: title,
      sourceFolder: sourceFolder,
      bucketsByStrongAlias: bucketsByStrongAlias,
      bucketsByTitleAlias: bucketsByTitleAlias,
    );
    if (bucket == null) {
      bucket = _MutableScriptBucket(
        scriptId: normalizedId,
        title: _fallback(title, '未命名剧本'),
        sourceFolder: sourceFolder ?? '',
        updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
      buckets.add(bucket);
    }
    bucket.merge(
      title: title,
      sourceFolder: sourceFolder,
      updatedAt: updatedAt,
    );
    registerAliases(
      bucket,
      scriptId: scriptId,
      title: title,
      sourceFolder: sourceFolder,
    );
    return bucket;
  }

  for (final script in scripts) {
    final bucket = bucketFor(
      scriptId: script.scriptId,
      title: script.name,
      sourceFolder: script.sourceFolder,
      updatedAt: script.updatedAt,
    );
    bucket.mergeCategories(script.categoryNames);
    bucket.mergeVersionLabels(script.exhibitionVersionLabels);
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
          imagePath: _defaultImagePathForSource(task.sourceFile),
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
          imagePath: _defaultImagePathForSource(sourceFile),
          statusLabel: sourceFile.exists ? '源文件' : '源文件缺失',
          updatedAt: script.updatedAt,
        ),
        versionDescription: sourceVersionDescription,
        versionUpdatedAt: script.updatedAt,
      );
    }
    for (final attachment in script.imageAttachments) {
      bucket.addItem(
        ScriptExhibitionItem(
          id: 'attachment-${script.scriptId}-${attachment.attachmentId}',
          scriptId: bucket.scriptId,
          scriptTitle: bucket.title,
          sourceFolder: bucket.sourceFolder,
          versionId: ScriptExhibitionVersion.attachmentsId,
          versionLabel: '剧本图片',
          sourceKind: ScriptExhibitionItemSourceKind.attachment,
          frameIndex: attachment.frameIndex,
          sourceFileName: attachment.sourceFileName,
          title: _fallback(
              attachment.label, _fileNameFromPath(attachment.imagePath)),
          subtitle: '挂接图片 · ${_dateLabel(attachment.createdAt)}',
          prompt: '',
          imagePath: attachment.imagePath,
          statusLabel: '已挂接',
          updatedAt: attachment.createdAt,
          imageAttachmentId: attachment.attachmentId,
        ),
        versionDescription: '手动导入并挂接在当前剧本下的图片版本。',
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
          prompt: _payloadPrompt(task.payload),
          imagePath: displayImagePath,
          statusLabel: _productionStatusLabel(task),
          updatedAt: task.updatedAt,
          productionPlanId: plan.id,
          recastRunId: source.recastRunId,
          taskId: task.id,
          galleryRecord: galleryRecord,
          assetCapturePayload: task.payload,
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

  final scriptsOut = buckets.map((bucket) => bucket.toScript()).toList()
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

  return ScriptExhibitionSnapshot(scripts: List.unmodifiable(scriptsOut));
}

class _MutableScriptBucket {
  final String scriptId;
  String title;
  String sourceFolder;
  DateTime updatedAt;
  final Map<String, _MutableVersionBucket> versions = {};
  final Set<String> categoryNames = {};
  final Map<String, String> versionLabelOverrides = {};

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
    if (version.id == ScriptExhibitionVersion.attachmentsId) return 1;
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

_MutableScriptBucket? _findScriptBucket({
  required String? scriptId,
  required String? title,
  required String? sourceFolder,
  required Map<String, _MutableScriptBucket> bucketsByStrongAlias,
  required Map<String, _MutableScriptBucket?> bucketsByTitleAlias,
}) {
  for (final alias in _scriptStrongAliases(
    scriptId: scriptId,
    sourceFolder: sourceFolder,
  )) {
    final bucket = bucketsByStrongAlias[alias];
    if (bucket != null) return bucket;
  }

  if (_hasText(sourceFolder)) return null;
  final titleAlias = _scriptTitleAlias(title);
  if (titleAlias == null) return null;
  return bucketsByTitleAlias[titleAlias];
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

String _defaultImagePathForSource(TokenizerSourceFile sourceFile) {
  final defaultImagePath = sourceFile.defaultImagePath.trim();
  if (defaultImagePath.isNotEmpty) {
    return defaultImagePath;
  }
  return sourceFile.kind == TokenizerScriptSourceKind.image
      ? sourceFile.path
      : '';
}

String _sourceVersionLabel(TokenizerScript script) {
  return _isImageOnlyScript(script) ? '默认版本' : '原始剧本';
}

String _sourceVersionDescription(TokenizerScript script) {
  return _isImageOnlyScript(script) ? '导入时保留的默认图片版本。' : '导入时保留的原始剧本帧。';
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
