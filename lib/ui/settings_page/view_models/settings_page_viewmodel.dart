import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/core/constants/settings.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/studio/services/prompt_translation_service.dart';
import 'package:novel_studio/data/studio/services/prompt_workshop_bridge.dart';
import 'package:novel_studio/data/studio/services/script_ai_connectivity_service.dart';
import 'package:novel_studio/data/studio/services/studio_cache_import_service.dart';
import 'package:novel_studio/data/studio/tools/online_ai_tools.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/core/app_display_settings.dart';
import 'package:novel_studio/ui/core/utils/flushbar.dart';

class SettingsPageViewmodel extends ChangeNotifier {
  PayloadConfig get payloadConfig => GetIt.I();
  ConfigService get configService => GetIt.I();
  final ScriptAiConnectivityService scriptAiConnectivityService;
  final TranslationCache translationCache;
  final PromptTranslationProviderRunner aiTranslationProvider;
  final Future<void> Function(TranslationCache cache) saveTranslationCache;
  final StudioCacheImportService cacheImportService;

  bool isTestingScriptAiConnection = false;
  String scriptAiTestStatus = '尚未测试连通性';
  bool isTestingTranslationAiConnection = false;
  String translationAiTestStatus = '尚未测试连通性';
  bool isRefreshingTranslationCacheWithAi = false;
  String translationCacheRefreshStatus = '尚未刷新翻译缓存';

  bool isImportingStudioCache = false;
  String studioCacheImportStatus = '尚未载入缓存包';

  SettingsPageViewmodel({
    ScriptAiConnectivityService? scriptAiConnectivityService,
    TranslationCache? translationCache,
    PromptTranslationProviderRunner? aiTranslationProvider,
    Future<void> Function(TranslationCache cache)? saveTranslationCache,
    StudioCacheImportService? cacheImportService,
  })  : scriptAiConnectivityService =
            scriptAiConnectivityService ?? DefaultScriptAiConnectivityService(),
        translationCache = translationCache ??
            (GetIt.I.isRegistered<TranslationCache>()
                ? GetIt.I<TranslationCache>()
                : TranslationCache()),
        aiTranslationProvider =
            aiTranslationProvider ?? buildAiTranslationProvider(),
        saveTranslationCache =
            saveTranslationCache ?? PromptWorkshopBridge.saveTranslationCache,
        cacheImportService = cacheImportService ?? StudioCacheImportService();

  Settings get settings {
    return payloadConfig.settings;
  }

  void setApiKey(String value) {
    payloadConfig.settings.apiKey = value.trim();
    notifyListeners();
  }

  void setScriptAiBaseUrl(String value) {
    payloadConfig.settings.scriptAiBaseUrl = value.trim();
    notifyListeners();
  }

  void setScriptAiToken(String value) {
    payloadConfig.settings.scriptAiToken = value.trim();
    notifyListeners();
  }

  void setScriptAiModel(String value) {
    payloadConfig.settings.scriptAiModel = value.trim();
    notifyListeners();
  }

  void setScriptAiReasoningEffort(String value) {
    payloadConfig.settings.scriptAiReasoningEffort =
        normalizeScriptAiReasoningEffort(value);
    notifyListeners();
  }

  void setTranslationAiBaseUrl(String value) {
    payloadConfig.settings.translationAiBaseUrl = value.trim();
    notifyListeners();
  }

  void setTranslationProvider(String value) {
    payloadConfig.settings.translationProvider =
        value == 'google' ? 'google' : 'ai';
    notifyListeners();
  }

  void setTranslationAiToken(String value) {
    payloadConfig.settings.translationAiToken = value.trim();
    notifyListeners();
  }

  void setTranslationAiModel(String value) {
    payloadConfig.settings.translationAiModel = value.trim();
    notifyListeners();
  }

  Future<void> testScriptAiConnection() async {
    final baseUrl = settings.scriptAiBaseUrl.trim();
    final token = settings.scriptAiToken.trim();
    final model = settings.scriptAiModel.trim();
    if (baseUrl.isEmpty || token.isEmpty || model.isEmpty) {
      scriptAiTestStatus = '请先填写剧本 AI 地址、Token 和模型';
      isTestingScriptAiConnection = false;
      notifyListeners();
      return;
    }

    isTestingScriptAiConnection = true;
    scriptAiTestStatus = '正在测试剧本 AI 连通性';
    notifyListeners();

    final result = await scriptAiConnectivityService.testConnection(
      ScriptAiConnectivityRequest(
        baseUrl: baseUrl,
        token: token,
        model: model,
        proxy: settings.proxy.trim(),
      ),
    );
    isTestingScriptAiConnection = false;
    scriptAiTestStatus =
        result.success ? '剧本 AI 连通性测试成功' : '剧本 AI 连通性测试失败：${result.message}';
    notifyListeners();
  }

  Future<void> testTranslationAiConnection() async {
    final baseUrl = settings.translationAiBaseUrl.trim();
    final token = settings.translationAiToken.trim();
    final model = settings.translationAiModel.trim();
    if (baseUrl.isEmpty || token.isEmpty || model.isEmpty) {
      translationAiTestStatus = '请先填写翻译 AI 地址、Token 和模型';
      isTestingTranslationAiConnection = false;
      notifyListeners();
      return;
    }

    isTestingTranslationAiConnection = true;
    translationAiTestStatus = '正在测试翻译 AI 连通性';
    notifyListeners();

    final result = await scriptAiConnectivityService.testConnection(
      ScriptAiConnectivityRequest(
        baseUrl: baseUrl,
        token: token,
        model: model,
        proxy: settings.proxy.trim(),
      ),
    );
    isTestingTranslationAiConnection = false;
    translationAiTestStatus =
        result.success ? '翻译 AI 连通性测试成功' : '翻译 AI 连通性测试失败：${result.message}';
    notifyListeners();
  }

  Future<void> refreshTranslationCacheWithAi() async {
    if (isRefreshingTranslationCacheWithAi) {
      return;
    }
    final baseUrl = settings.translationAiBaseUrl.trim();
    final token = settings.translationAiToken.trim();
    final model = settings.translationAiModel.trim();
    if (baseUrl.isEmpty || token.isEmpty || model.isEmpty) {
      translationCacheRefreshStatus = '请先填写翻译 AI 地址、Token 和模型';
      notifyListeners();
      return;
    }

    final cachedEntries = translationCache.entries.entries.toList();
    if (cachedEntries.isEmpty) {
      translationCacheRefreshStatus = '暂无翻译缓存可更新';
      notifyListeners();
      return;
    }

    isRefreshingTranslationCacheWithAi = true;
    var successCount = 0;
    var failedCount = 0;
    translationCacheRefreshStatus = '正在 AI 重译缓存 0/${cachedEntries.length}';
    notifyListeners();

    for (final entry in cachedEntries) {
      final sourceText = TranslationCache.textFromCacheKey(entry.key);
      if (sourceText.isEmpty) {
        failedCount += 1;
      } else {
        try {
          final result = await aiTranslationProvider(
            OnlineTranslationRequest(
              text: sourceText,
              sourceLanguage: 'en',
              targetLanguage: 'zh',
            ),
            settings,
          );
          final translated = result.translatedText.trim();
          if (translated.isEmpty) {
            failedCount += 1;
          } else {
            translationCache.setCached(
              sourceText,
              translated,
              source: 'ai-refresh',
            );
            successCount += 1;
          }
        } catch (_) {
          failedCount += 1;
        }
      }

      final processed = successCount + failedCount;
      if (processed == cachedEntries.length || processed % 10 == 0) {
        translationCacheRefreshStatus =
            '正在 AI 重译缓存 $processed/${cachedEntries.length}';
        notifyListeners();
      }
    }

    if (successCount > 0) {
      await saveTranslationCache(translationCache);
    }
    isRefreshingTranslationCacheWithAi = false;
    translationCacheRefreshStatus = failedCount == 0
        ? 'AI 更新缓存完成：$successCount 条'
        : 'AI 更新缓存完成：$successCount 条，$failedCount 条失败';
    notifyListeners();
  }

  void setBatchCount(String value) {
    final parseResult = int.tryParse(value);
    if (parseResult == null) return;
    payloadConfig.settings.batchCount = parseResult;
    notifyListeners();
  }

  void setBatchIntervalSet(String value) {
    final parseResult = int.tryParse(value);
    if (parseResult == null) return;
    payloadConfig.settings.batchIntervalSec = parseResult;
    notifyListeners();
  }

  void setBatchIntervalJitterMin(String value) {
    final parseResult = int.tryParse(value);
    if (parseResult == null) return;
    payloadConfig.settings.batchIntervalJitterMinSec = max(0, parseResult);
    notifyListeners();
  }

  void setBatchIntervalJitterMax(String value) {
    final parseResult = int.tryParse(value);
    if (parseResult == null) return;
    payloadConfig.settings.batchIntervalJitterMaxSec = max(0, parseResult);
    notifyListeners();
  }

  void setRetryOn429Enabled(bool? value) {
    if (value == null) return;
    payloadConfig.settings.retryOn429Enabled = value;
    notifyListeners();
  }

  void setRetryOn429DelaySec(String value) {
    final parseResult = int.tryParse(value);
    if (parseResult == null) return;
    payloadConfig.settings.retryOn429DelaySec = max(1, parseResult);
    notifyListeners();
  }

  void setNumberOfRequests(String value) {
    final parseResult = int.tryParse(value);
    if (parseResult == null) return;
    payloadConfig.settings.numberOfRequests = parseResult;
    notifyListeners();
  }

  void setEraseMetadataEnabled(bool? value) {
    if (value == null) return;
    payloadConfig.settings.metadataEraseEnabled = value;
    notifyListeners();
  }

  void setCustomMetadataEnabled(bool? value) {
    if (value == null) return;
    payloadConfig.settings.customMetadataEnabled = value;
    notifyListeners();
  }

  void setCustomMetadataContent(String value) {
    payloadConfig.settings.customMetadataContent = value;
    notifyListeners();
  }

  void pickOutputFolderPath() async {
    final pickResult = await FilePicker.platform.getDirectoryPath();
    if (pickResult == null) return;
    payloadConfig.settings.outputFolderPath = pickResult;
    notifyListeners();
  }

  void setProxy(String value) {
    final proxy = value.trim();

    bool isValidProxy(String input) {
      if (input == '') return true;
      final ipPortRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}:\d{1,5}$');
      if (!ipPortRegex.hasMatch(input)) return false;
      return true;
    }

    if (!isValidProxy(proxy)) return;
    payloadConfig.settings.proxy = proxy;
    notifyListeners();
  }

  void loadJsonConfig(BuildContext context) async {
    FilePickerResult? result =
        await FilePicker.platform.pickFiles(withData: true);
    if (result == null) return;
    try {
      var fileContent = utf8.decode(result.files.single.bytes!);
      Map<String, dynamic> jsonData = json.decode(fileContent);
      loadImportedJson(jsonData);
      if (!context.mounted) return;
      showInfoBar(context, '${tr('info_import_file')}${tr('succeed')}');
    } catch (error) {
      if (!context.mounted) return;
      showErrorBar(context,
          '${tr('info_import_file')}${tr('failed')}: ${error.toString()}');
    }
  }

  void loadImportedJson(Map<String, dynamic> jsonData) {
    payloadConfig.loadJson(jsonData, preserveCurrentApiKey: true);
    notifyListeners();
  }

  void importStudioCacheFromDirectory(BuildContext context) async {
    final pickResult = await FilePicker.platform.getDirectoryPath();
    if (pickResult == null) return;
    try {
      final result = await importStudioCacheDirectoryPath(pickResult);
      if (!context.mounted) return;
      showInfoBar(context, '缓存包载入完成：${result.importedFiles} 个文件');
    } catch (error) {
      if (!context.mounted) return;
      showErrorBar(context, '缓存包载入失败：${error.toString()}');
    }
  }

  void importStudioCacheFromZip(BuildContext context) async {
    final pickResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = pickResult?.files.single.path;
    if (path == null) return;
    try {
      final result = await importStudioCacheZipPath(path);
      if (!context.mounted) return;
      showInfoBar(context, '缓存包载入完成：${result.importedFiles} 个文件');
    } catch (error) {
      if (!context.mounted) return;
      showErrorBar(context, '缓存包载入失败：${error.toString()}');
    }
  }

  Future<StudioCacheImportResult> importStudioCacheDirectoryPath(
    String path,
  ) {
    return _importStudioCache(
      () => cacheImportService.importFromDirectory(
        Directory(path),
        targetRoot: _currentWorkspaceRoot(),
      ),
    );
  }

  Future<StudioCacheImportResult> importStudioCacheZipPath(String path) {
    return _importStudioCache(
      () => cacheImportService.importFromZip(
        File(path),
        targetRoot: _currentWorkspaceRoot(),
      ),
    );
  }

  Future<StudioCacheImportResult> _importStudioCache(
    Future<StudioCacheImportResult> Function() importer,
  ) async {
    if (isImportingStudioCache) {
      throw StateError('Cache import is already running.');
    }
    final workspaceRoot = _currentWorkspaceRoot();
    isImportingStudioCache = true;
    studioCacheImportStatus = '正在载入缓存包...';
    notifyListeners();
    try {
      final result = await importer();
      final workspaceService = GetIt.I<WorkspaceService>();
      await workspaceService.openWorkspace(workspaceRoot.path);
      final backupText =
          result.backupPath == null ? '' : '，已备份旧工作区：${result.backupPath}';
      studioCacheImportStatus =
          '缓存包载入完成：${result.importedFiles} 个文件$backupText';
      return result;
    } catch (error) {
      studioCacheImportStatus = '缓存包载入失败：${error.toString()}';
      rethrow;
    } finally {
      isImportingStudioCache = false;
      notifyListeners();
    }
  }

  Directory _currentWorkspaceRoot() {
    if (!GetIt.I.isRegistered<WorkspaceService>()) {
      throw StateError('Workspace service is not ready.');
    }
    final root = GetIt.I<WorkspaceService>().root;
    if (root == null) {
      throw StateError('No Novel Studio workspace is open.');
    }
    return root;
  }

  void setFileNamePrefixKey(String value) {
    payloadConfig.settings.fileNamePrefixKey = value;
    notifyListeners();
  }

  void saveJsonConfig() {
    final configJson = payloadConfig.toJson();
    final filename =
        'nai-generator-config-${FileService().generateRandomString()}.json';
    FileService().saveStringToFile(
      json.encode(configJson),
      filename,
    );
  }

  void setThemeMode(String value, BuildContext context) {
    payloadConfig.settings.themeMode = value;
    AdaptiveTheme.of(context).setThemeMode(stringToThemeMode[value]!);
    notifyListeners();
  }

  void setUiTextScale(double value) {
    final next = AppDisplaySettings.clampTextScale(value);
    payloadConfig.settings.uiTextScale = next;
    AppDisplaySettings.setTextScale(next);
    if (GetIt.I.isRegistered<ConfigService>()) {
      configService.saveConfig(payloadConfig.toJson());
    }
    notifyListeners();
  }

  void notify() => notifyListeners();

  void saveCurrentConfig() {
    configService.saveConfig(payloadConfig.toJson());
  }
}
