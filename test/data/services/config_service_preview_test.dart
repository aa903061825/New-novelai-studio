import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/services/config_service.dart';

void main() {
  test('SavedConfigInfo preserves preview images and selected cover in JSON',
      () {
    final info = SavedConfigInfo(
      title: 'Cyber Princess',
      lastModified: DateTime.parse('2026-05-19T10:30:00Z'),
      previewImages: const ['thumb-a', 'thumb-b'],
      previewCoverIndex: 1,
    );

    final restored = SavedConfigInfo.fromJson(info.toJson());

    expect(restored.title, 'Cyber Princess');
    expect(restored.lastModified, DateTime.parse('2026-05-19T10:30:00Z'));
    expect(restored.previewImages, ['thumb-a', 'thumb-b']);
    expect(restored.previewCoverIndex, 1);
    expect(restored.coverPreviewImage, 'thumb-b');
  });

  test('SavedConfigInfo falls back safely when preview JSON is malformed', () {
    final info = SavedConfigInfo.fromJson({
      'title': 'Broken Preview',
      'lastModified': 'not-a-date',
      'previewImages': ['thumb-a', 123, '', null],
      'previewCoverIndex': 99,
    });

    expect(info.title, 'Broken Preview');
    expect(info.lastModified, DateTime.fromMicrosecondsSinceEpoch(0));
    expect(info.previewImages, ['thumb-a']);
    expect(info.previewCoverIndex, 0);
    expect(info.coverPreviewImage, 'thumb-a');
  });

  group('ConfigService preview metadata', () {
    late Directory tempDir;
    late Box<dynamic> testBox;
    late ConfigService configService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'novel-studio-config-preview-test-',
      );
      Hive.init(tempDir.path);
      testBox = await Hive.openBox('savedBox-test-config-preview');
      configService = ConfigService()
        ..saveBox = testBox
        ..currentUuid = 'active'
        ..configIndex = {
          'active': SavedConfigInfo(
            title: 'Active',
            lastModified: DateTime.parse('2026-05-19T09:00:00Z'),
          ),
        };
    });

    tearDown(() async {
      await testBox.deleteFromDisk();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('updates and reloads config preview images', () {
      configService.updateConfigPreviewByUuid(
        'active',
        previewImages: const ['thumb-a', 'thumb-b'],
        previewCoverIndex: 1,
      );

      final reloadedIndex = configService.loadConfigIndex();
      final reloadedInfo = reloadedIndex['active'];

      expect(reloadedInfo, isNotNull);
      expect(reloadedInfo!.previewImages, ['thumb-a', 'thumb-b']);
      expect(reloadedInfo.previewCoverIndex, 1);
      expect(reloadedInfo.coverPreviewImage, 'thumb-b');
    });

    test('updates only the selected preview cover', () {
      configService.updateConfigPreviewByUuid(
        'active',
        previewImages: const ['thumb-a', 'thumb-b'],
        previewCoverIndex: 1,
      );

      configService.setConfigPreviewCoverIndex('active', 0);

      expect(configService.configIndex['active']!.previewImages, [
        'thumb-a',
        'thumb-b',
      ]);
      expect(configService.configIndex['active']!.previewCoverIndex, 0);
      expect(configService.configIndex['active']!.coverPreviewImage, 'thumb-a');
    });

    test('saveConfig keeps the uuid captured before its first await', () async {
      configService.currentUuid = 'source-config';

      final save = configService.saveConfig({'name': 'source payload'});
      configService.currentUuid = 'other-config';
      await save;

      expect(
        configService.loadConfigByUuid('source-config'),
        {'name': 'source payload'},
      );
      expect(configService.loadConfigByUuid('other-config'), isNull);
    });

    test('saveConfigByUuid allows an immediate title update', () async {
      final save = configService.saveConfigByUuid(
        'copied-config',
        {'name': 'copy payload'},
      );

      configService.renameConfigByUuid('copied-config', 'Copied config');
      await save;

      expect(
          configService.configIndex['copied-config']!.title, 'Copied config');
      expect(
        configService.loadConfigIndex()['copied-config']!.title,
        'Copied config',
      );
    });

    test('deleteConfigByUuid persists the removed index entry', () async {
      await configService.saveConfigByUuid(
        'deleted-config',
        {'name': 'delete me'},
      );
      configService.renameConfigByUuid('deleted-config', 'Delete me');
      await Future<void>.delayed(Duration.zero);

      configService.deleteConfigByUuid('deleted-config');
      await Future<void>.delayed(Duration.zero);

      expect(
          configService.loadConfigIndex(), isNot(contains('deleted-config')));
      expect(configService.loadConfigByUuid('deleted-config'), isNull);
    });

    test('migrates the active model to Novel 5 only once', () async {
      final config = <String, dynamic>{
        'param_config': <String, dynamic>{
          'model': 'nai-diffusion-4-curated-preview',
        },
      };

      expect(
        await configService.migrateCurrentConfigToNovel5DefaultIfNeeded(config),
        isTrue,
      );
      expect(
        (config['param_config'] as Map)['model'],
        defaultGenerationModel,
      );
      expect(
        configService.loadConfigByUuid('active')?['param_config']['model'],
        defaultGenerationModel,
      );

      (config['param_config'] as Map)['model'] = 'nai-diffusion-4-5-full';
      expect(
        await configService.migrateCurrentConfigToNovel5DefaultIfNeeded(config),
        isFalse,
      );
      expect(
        (config['param_config'] as Map)['model'],
        'nai-diffusion-4-5-full',
      );
    });
  });
}
