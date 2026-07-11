import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:novel_studio/data/models/generation_runtime_state.dart';
import 'package:novel_studio/data/models/global_generation_params.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/services/vibe_source_image_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class SavedConfigInfo {
  String title;
  DateTime lastModified;
  List<String> previewImages;
  int previewCoverIndex;

  SavedConfigInfo({
    required this.title,
    required this.lastModified,
    this.previewImages = const [],
    this.previewCoverIndex = 0,
  });

  factory SavedConfigInfo.fromJson(Map<String, dynamic> json) {
    final jsonDate = DateTime.tryParse(json['lastModified'] ?? '');
    final previewImages = _parsePreviewImages(json['previewImages']);
    final previewCoverIndex = _normalizeCoverIndex(
      json['previewCoverIndex'],
      previewImages.length,
    );
    return SavedConfigInfo(
      title: json['title'] ?? 'Unnamed',
      lastModified: jsonDate ?? DateTime.fromMicrosecondsSinceEpoch(0),
      previewImages: previewImages,
      previewCoverIndex: previewCoverIndex,
    );
  }

  factory SavedConfigInfo.fromEmpty() {
    return SavedConfigInfo(
      title: 'Unnamed',
      lastModified: DateTime.fromMicrosecondsSinceEpoch(0),
    );
  }

  String? get coverPreviewImage {
    if (previewImages.isEmpty) return null;
    if (previewCoverIndex < 0 || previewCoverIndex >= previewImages.length) {
      return previewImages.first;
    }
    return previewImages[previewCoverIndex];
  }

  void setPreviewImages({
    required List<String> images,
    required int coverIndex,
  }) {
    previewImages = _parsePreviewImages(images);
    previewCoverIndex = _normalizeCoverIndex(coverIndex, previewImages.length);
  }

  void setPreviewCoverIndex(int coverIndex) {
    previewCoverIndex = _normalizeCoverIndex(coverIndex, previewImages.length);
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'lastModified': lastModified.toIso8601String(),
      if (previewImages.isNotEmpty) 'previewImages': previewImages,
      if (previewImages.isNotEmpty) 'previewCoverIndex': previewCoverIndex,
    };
  }

  static List<String> _parsePreviewImages(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<String>()
        .where((image) => image.trim().isNotEmpty)
        .take(9)
        .toList(growable: false);
  }

  static int _normalizeCoverIndex(dynamic value, int imageCount) {
    if (imageCount <= 0) return 0;
    final index = value is int
        ? value
        : value is String
            ? int.tryParse(value) ?? 0
            : 0;
    if (index < 0 || index >= imageCount) return 0;
    return index;
  }
}

class ConfigService {
  static const _globalGenerationParamsKey = 'globalGenerationParams';
  static const _generationRuntimeStateKey = 'generationRuntimeState';
  late PackageInfo packageInfo;
  late Box saveBox;

  late String currentUuid;
  late Map<String, SavedConfigInfo> configIndex;
  bool get _hasSaveBox {
    try {
      saveBox;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> loadDefaultConfig() async {
    return await rootBundle.loadString('assets/json/example.json');
  }

  Future<Map<String, dynamic>> loadSavedConfig() async {
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
    saveBox = await Hive.openBox('savedBox');
    configIndex = loadConfigIndex();
    String? savedUuid = saveBox.get('savedUuid');
    String? jsonData;

    // Load saved config, or use example config
    if (savedUuid == null) {
      jsonData = saveBox.get('savedConfig');
    } else {
      jsonData = saveBox.get('savedConfig-$savedUuid');
    }
    jsonData ??= await loadDefaultConfig();
    final decodedConfig = await _decodeConfigJson(jsonData);

    // Set current UUID
    if (savedUuid == null) {
      currentUuid = const Uuid().v4();
      await saveConfig(decodedConfig);
    } else {
      currentUuid = savedUuid;
    }
    await saveBox.delete('savedConfig');

    if (kDebugMode) {
      print('Loaded keys:\n${saveBox.keys.toList().join('\n')}');
      print('Config indexes: ${configIndex.toString()}');
      print('Saved UUID: $savedUuid');
    }

    return decodedConfig;
  }

  Future<void> saveConfig(Map<String, dynamic> jsonData) async {
    if (!_hasSaveBox) return;
    final targetUuid = currentUuid;
    await saveBox.put('savedUuid', targetUuid);
    await saveConfigByUuid(targetUuid, jsonData);
  }

  Future<String> saveV4VibeSourceImage({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    return VibeSourceImageStore(rootDirectory: dir).savePng(
      configUuid: _hasSaveBox ? currentUuid : 'current',
      fileName: fileName,
      bytes: bytes,
    );
  }

  Future<bool> externalizeV4VibeSourceImages(
      PayloadConfig payloadConfig) async {
    final dir = await getApplicationDocumentsDirectory();
    return VibeSourceImageStore(rootDirectory: dir).externalizeV4Vibes(
      configUuid: _hasSaveBox ? currentUuid : 'current',
      vibes: payloadConfig.vibeConfigListV4,
    );
  }

  /// Returns
  ///
  /// {'uuid1': {'title': 'title1', 'lastModified': 'timestamp1'}, 'uuid2': ..., ...}
  Map<String, SavedConfigInfo> loadConfigIndex() {
    if (!_hasSaveBox) return {};
    final jsonString = saveBox.get('configIndex');
    if (jsonString == null) {
      return {};
    }
    try {
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      return jsonData.cast<String, Map<String, dynamic>>().map(
            (uuid, configInfoJson) => MapEntry(
              uuid,
              SavedConfigInfo.fromJson(configInfoJson),
            ),
          );
    } catch (e) {
      if (kDebugMode) {
        print('Error loading config indexes: $e');
      }
      return {};
    }
  }

  void saveConfigIndex() {
    if (!_hasSaveBox) return;
    final encodedIndex = configIndex.map(
      (uuid, savedConfigInfo) => MapEntry(
        uuid,
        savedConfigInfo.toJson(),
      ),
    );
    saveBox.put('configIndex', json.encode(encodedIndex));
  }

  Map<String, dynamic>? loadConfigByUuid(String uuid) {
    if (!_hasSaveBox) return null;
    final configJsonString = saveBox.get('savedConfig-$uuid');
    if (configJsonString == null) {
      return null;
    }
    return json.decode(configJsonString);
  }

  void renameConfigByUuid(String uuid, String title) {
    if (!configIndex.containsKey(uuid)) return;
    configIndex[uuid]!.title = title;
    saveConfigIndex();
  }

  void updateConfigPreviewByUuid(
    String uuid, {
    required List<String> previewImages,
    required int previewCoverIndex,
  }) {
    final configInfo = configIndex[uuid];
    if (configInfo == null) return;
    configInfo.setPreviewImages(
      images: previewImages,
      coverIndex: previewCoverIndex,
    );
    saveConfigIndex();
  }

  void setConfigPreviewCoverIndex(String uuid, int previewCoverIndex) {
    final configInfo = configIndex[uuid];
    if (configInfo == null) return;
    configInfo.setPreviewCoverIndex(previewCoverIndex);
    saveConfigIndex();
  }

  Future<void> saveConfigByUuid(
      String uuid, Map<String, dynamic> jsonData) async {
    if (!_hasSaveBox) return;
    if (kDebugMode) {
      print('Saving config: $uuid');
    }
    if (!configIndex.containsKey(uuid)) {
      configIndex[uuid] = SavedConfigInfo.fromEmpty();
    }
    configIndex[uuid]!.lastModified = DateTime.now();
    await saveBox.put('savedConfig-$uuid', json.encode(jsonData));
    saveConfigIndex();
  }

  void deleteConfigByUuid(String uuid) {
    if (!_hasSaveBox) return;
    if (uuid == currentUuid) return;
    saveBox.delete('savedConfig-$uuid');
    configIndex.remove(uuid);
    saveConfigIndex();
  }

  GlobalGenerationParams? loadGlobalGenerationParams() {
    if (!_hasSaveBox) return null;
    final jsonString = saveBox.get(_globalGenerationParamsKey);
    if (jsonString == null) {
      return null;
    }
    return GlobalGenerationParams.fromJson(
      (json.decode(jsonString) as Map).cast<String, dynamic>(),
    );
  }

  void saveGlobalGenerationParams(GlobalGenerationParams params) {
    if (!_hasSaveBox) return;
    saveBox.put(_globalGenerationParamsKey, json.encode(params.toJson()));
  }

  GenerationRuntimeState? loadGenerationRuntimeState() {
    if (!_hasSaveBox) return null;
    final jsonString = saveBox.get(_generationRuntimeStateKey);
    if (jsonString == null) {
      return null;
    }
    try {
      return GenerationRuntimeState.fromJson(
        (json.decode(jsonString) as Map).cast<String, dynamic>(),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error loading generation runtime state: $e');
      }
      return null;
    }
  }

  void saveGenerationRuntimeState(GenerationRuntimeState state) {
    if (!_hasSaveBox) return;
    saveBox.put(_generationRuntimeStateKey, json.encode(state.toJson()));
  }

  Future<void> saveGenerationRuntimeStateAsync(
    GenerationRuntimeState state,
  ) async {
    if (!_hasSaveBox) return;
    await saveBox.put(_generationRuntimeStateKey, json.encode(state.toJson()));
  }

  Future<Map<String, dynamic>> _decodeConfigJson(String jsonData) async {
    if (jsonData.length < _backgroundConfigDecodeThreshold) {
      return (json.decode(jsonData) as Map).cast<String, dynamic>();
    }
    return compute(_configJsonFromString, jsonData);
  }
}

const _backgroundConfigDecodeThreshold = 1024 * 1024;

Map<String, dynamic> _configJsonFromString(String source) {
  return (json.decode(source) as Map).cast<String, dynamic>();
}
