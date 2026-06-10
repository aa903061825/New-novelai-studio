import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/studio/services/studio_cache_import_service.dart';
import 'package:nai_casrand/data/studio/tools/online_ai_tools.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/data/studio/services/script_ai_connectivity_service.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/settings_page/view_models/settings_page_viewmodel.dart';

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton(
      PayloadConfig(
        rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
        characterConfigList: const [],
        savedPromptConfigList: const [],
        paramConfig: ParamConfig(),
        settings: Settings.fromJson({}),
        overridePrompt: '',
        useOverridePrompt: false,
        useCharacterPromptWithOverride: false,
      ),
    );
    GetIt.I.registerSingleton(ConfigService());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('sets batch interval jitter values from numeric input', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setBatchIntervalJitterMin('10');
    viewmodel.setBatchIntervalJitterMax('40');

    expect(viewmodel.settings.batchIntervalJitterMinSec, 10);
    expect(viewmodel.settings.batchIntervalJitterMaxSec, 40);
  });

  test('clamps negative jitter values to zero', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setBatchIntervalJitterMin('-3');
    viewmodel.setBatchIntervalJitterMax('-9');

    expect(viewmodel.settings.batchIntervalJitterMinSec, 0);
    expect(viewmodel.settings.batchIntervalJitterMaxSec, 0);
  });

  test('ignores invalid jitter input and keeps existing values', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setBatchIntervalJitterMin('10');
    viewmodel.setBatchIntervalJitterMax('40');
    viewmodel.setBatchIntervalJitterMin('abc');
    viewmodel.setBatchIntervalJitterMax('4.5');

    expect(viewmodel.settings.batchIntervalJitterMinSec, 10);
    expect(viewmodel.settings.batchIntervalJitterMaxSec, 40);
  });

  test('jitter setters notify listeners after successful updates', () {
    final viewmodel = SettingsPageViewmodel();
    var notificationCount = 0;

    viewmodel.addListener(() {
      notificationCount++;
    });

    viewmodel.setBatchIntervalJitterMin('10');
    viewmodel.setBatchIntervalJitterMax('40');

    expect(notificationCount, 2);
  });

  test('sets retry-on-429 settings from input', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setRetryOn429Enabled(true);
    viewmodel.setRetryOn429DelaySec('15');

    expect(viewmodel.settings.retryOn429Enabled, isTrue);
    expect(viewmodel.settings.retryOn429DelaySec, 15);
  });

  test('retry-on-429 delay ignores invalid input and clamps to at least 1', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setRetryOn429DelaySec('10');
    viewmodel.setRetryOn429DelaySec('abc');
    expect(viewmodel.settings.retryOn429DelaySec, 10);

    viewmodel.setRetryOn429DelaySec('0');
    expect(viewmodel.settings.retryOn429DelaySec, 1);
  });

  test('sets script and translation ai settings', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setApiKey(' pst-novelai-token ');
    viewmodel.setScriptAiBaseUrl('https://script.example/v1');
    viewmodel.setScriptAiToken('script-token');
    viewmodel.setScriptAiModel(' gpt-4.1-mini ');
    viewmodel.setTranslationProvider('google');
    viewmodel.setTranslationAiBaseUrl('https://translate.example/v1');
    viewmodel.setTranslationAiToken('translation-token');
    viewmodel.setTranslationAiModel(' gpt-4.1-mini ');

    expect(viewmodel.settings.apiKey, 'pst-novelai-token');
    expect(viewmodel.settings.scriptAiBaseUrl, 'https://script.example/v1');
    expect(viewmodel.settings.scriptAiToken, 'script-token');
    expect(viewmodel.settings.scriptAiModel, 'gpt-4.1-mini');
    expect(viewmodel.settings.translationProvider, 'google');
    expect(
      viewmodel.settings.translationAiBaseUrl,
      'https://translate.example/v1',
    );
    expect(viewmodel.settings.translationAiToken, 'translation-token');
    expect(viewmodel.settings.translationAiModel, 'gpt-4.1-mini');
  });

  test('tests script ai connection and reports success', () async {
    ScriptAiConnectivityRequest? captured;
    final viewmodel = SettingsPageViewmodel(
      scriptAiConnectivityService: _FakeScriptAiConnectivityService(
        (request) async {
          captured = request;
          return const ScriptAiConnectivityResult(
            success: true,
            message: '连接成功',
          );
        },
      ),
    );
    viewmodel.setScriptAiBaseUrl('https://script.example/v1');
    viewmodel.setScriptAiToken('script-token');
    viewmodel.setScriptAiModel('gpt-4.1-mini');
    viewmodel.setProxy('127.0.0.1:7890');

    await viewmodel.testScriptAiConnection();

    expect(captured?.baseUrl, 'https://script.example/v1');
    expect(captured?.token, 'script-token');
    expect(captured?.model, 'gpt-4.1-mini');
    expect(captured?.proxy, '127.0.0.1:7890');
    expect(viewmodel.scriptAiTestStatus, contains('成功'));
    expect(viewmodel.isTestingScriptAiConnection, isFalse);
  });

  test('script ai connection test validates required settings', () async {
    final viewmodel = SettingsPageViewmodel(
      scriptAiConnectivityService: _FakeScriptAiConnectivityService(
        (_) async => throw StateError('network should not run'),
      ),
    );

    await viewmodel.testScriptAiConnection();

    expect(viewmodel.scriptAiTestStatus, contains('请先填写'));
    expect(viewmodel.isTestingScriptAiConnection, isFalse);
  });

  test('tests translation ai connection and reports success', () async {
    ScriptAiConnectivityRequest? captured;
    final viewmodel = SettingsPageViewmodel(
      scriptAiConnectivityService: _FakeScriptAiConnectivityService(
        (request) async {
          captured = request;
          return const ScriptAiConnectivityResult(
            success: true,
            message: '连接成功',
          );
        },
      ),
    );
    viewmodel.setTranslationAiBaseUrl('https://translate.example/v1');
    viewmodel.setTranslationAiToken('translation-token');
    viewmodel.setTranslationAiModel('gpt-4.1-mini');
    viewmodel.setProxy('127.0.0.1:7890');

    await viewmodel.testTranslationAiConnection();

    expect(captured?.baseUrl, 'https://translate.example/v1');
    expect(captured?.token, 'translation-token');
    expect(captured?.model, 'gpt-4.1-mini');
    expect(captured?.proxy, '127.0.0.1:7890');
    expect(viewmodel.translationAiTestStatus, contains('成功'));
    expect(viewmodel.isTestingTranslationAiConnection, isFalse);
  });

  test('translation ai connection test validates required settings', () async {
    final viewmodel = SettingsPageViewmodel(
      scriptAiConnectivityService: _FakeScriptAiConnectivityService(
        (_) async => throw StateError('network should not run'),
      ),
    );

    await viewmodel.testTranslationAiConnection();

    expect(viewmodel.translationAiTestStatus, contains('请先填写'));
    expect(viewmodel.isTestingTranslationAiConnection, isFalse);
  });

  test('AI refresh rewrites every translation cache entry', () async {
    final cache = TranslationCache(clock: () => 1710000000)
      ..setCached('blue eyes', '旧蓝眼', source: 'manual')
      ..setCached('red dress', '旧红裙', source: 'manual');
    final translated = <String>[];
    var saved = false;
    final viewmodel = SettingsPageViewmodel(
      translationCache: cache,
      aiTranslationProvider: (request, settings) async {
        translated.add(request.text);
        return OnlineTranslationProviderResult(
          translatedText: 'AI ${request.text}',
          providerName: 'ai',
        );
      },
      saveTranslationCache: (cache) async {
        saved = true;
      },
    );
    viewmodel.setTranslationAiBaseUrl('https://translate.example/v1');
    viewmodel.setTranslationAiToken('translation-token');
    viewmodel.setTranslationAiModel('gpt-4.1-mini');

    await viewmodel.refreshTranslationCacheWithAi();

    expect(translated, ['blue eyes', 'red dress']);
    expect(cache.getCached('blue eyes'), 'AI blue eyes');
    expect(cache.getCached('red dress'), 'AI red dress');
    expect(cache.entryFor('blue eyes')!.source, 'ai-refresh');
    expect(saved, isTrue);
    expect(viewmodel.translationCacheRefreshStatus, contains('完成'));
    expect(viewmodel.isRefreshingTranslationCacheWithAi, isFalse);
  });

  test('loadImportedJson preserves current api key', () {
    final viewmodel = SettingsPageViewmodel();
    viewmodel.settings.apiKey = 'current-key';

    viewmodel.loadImportedJson({
      'prompt_config': {
        'selectionMethod': 'single',
        'shuffled': false,
        'prob': 0.0,
        'num': 1,
        'randomBracketsUpper': 0,
        'randomBracketsLower': 0,
        'type': 'str',
        'comment': 'imported',
        'filter': '',
        'strs': ['imported prompt'],
        'prompts': [],
        'enabled': true,
      },
      'character_config': const [],
      'saved_config': const [],
      'param_config': ParamConfig().toJson(),
      'settings': {
        'api_key': 'imported-key',
        'proxy': '127.0.0.1:7890',
      },
    });

    expect(viewmodel.settings.apiKey, 'current-key');
    expect(viewmodel.settings.proxy, '127.0.0.1:7890');
    expect(viewmodel.payloadConfig.rootPromptConfig.comment, 'imported');
  });

  test('imports studio cache directory into the current workspace', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'settings-cache-import-',
    );
    try {
      final workspaceRoot = Directory('${tempDir.path}/workspace');
      final sourceRoot = Directory('${tempDir.path}/cache/novel_studio');
      final workspaceService = WorkspaceService();
      await workspaceService.createWorkspace(workspaceRoot.path);
      await _writeText(
        sourceRoot,
        WorkspacePaths.manifest,
        '{"name":"Imported Studio","schemaVersion":1}',
      );
      await _writeText(
        sourceRoot,
        WorkspacePaths.characters,
        '[{"id":"imported","name":"Imported Character","traits":{}}]',
      );
      if (GetIt.I.isRegistered<WorkspaceService>()) {
        GetIt.I.unregister<WorkspaceService>();
      }
      GetIt.I.registerSingleton<WorkspaceService>(workspaceService);
      final viewmodel = SettingsPageViewmodel(
        cacheImportService: StudioCacheImportService(
          clock: () => DateTime.utc(2026, 6, 9, 13),
        ),
      );

      await viewmodel.importStudioCacheDirectoryPath(tempDir.path);

      final characters = await workspaceService.loadCharacters();
      expect(characters.single.name, 'Imported Character');
      expect(viewmodel.studioCacheImportStatus, contains('2'));
      expect(viewmodel.isImportingStudioCache, isFalse);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

class _FakeScriptAiConnectivityService implements ScriptAiConnectivityService {
  final Future<ScriptAiConnectivityResult> Function(
    ScriptAiConnectivityRequest request,
  ) handler;

  const _FakeScriptAiConnectivityService(this.handler);

  @override
  Future<ScriptAiConnectivityResult> testConnection(
    ScriptAiConnectivityRequest request,
  ) {
    return handler(request);
  }
}

Future<void> _writeText(
  Directory root,
  String relativePath,
  String content,
) async {
  final file = File('${root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
