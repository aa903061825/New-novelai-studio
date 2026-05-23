import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nai_casrand/data/services/config_service.dart';

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
        'nai-casrand-config-preview-test-',
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
  });
}
