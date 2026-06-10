import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/vibe_config_v4.dart';
import 'package:nai_casrand/data/services/vibe_source_image_store.dart';

void main() {
  test('VibeSourceImageStore saves imported PNG bytes as an explicit file',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('vibe-store-test-');
    addTearDown(() => tempDir.delete(recursive: true));
    final store = VibeSourceImageStore(rootDirectory: tempDir);
    final sourceBytes = Uint8List.fromList(const [137, 80, 78, 71, 1, 2, 3]);

    final savedPath = await store.savePng(
      configUuid: 'config-123',
      fileName: '主 Vibe 图.png',
      bytes: sourceBytes,
    );

    final savedFile = File(savedPath);
    expect(savedFile.existsSync(), isTrue);
    expect(savedFile.readAsBytesSync(), sourceBytes);
    expect(savedPath, contains('vibe-assets'));
    expect(savedPath, contains('config-123'));
    expect(savedPath.endsWith('.png'), isTrue);
  });

  test('VibeSourceImageStore externalizes legacy V4 image bytes', () async {
    final tempDir = await Directory.systemTemp.createTemp('vibe-store-test-');
    addTearDown(() => tempDir.delete(recursive: true));
    final store = VibeSourceImageStore(rootDirectory: tempDir);
    final sourceBytes = Uint8List.fromList(const [1, 2, 3, 4]);
    final config = VibeConfigV4(
      fileName: 'legacy.png',
      vibeB64: 'vibe',
      referenceStrength: 0.2,
      imageBytes: sourceBytes,
    );

    final changed = await store.externalizeV4Vibes(
      configUuid: 'config-123',
      vibes: [config],
    );

    expect(changed, isTrue);
    expect(config.imageBytes, isNull);
    expect(config.sourceImagePath, isNotNull);
    expect(File(config.sourceImagePath!).readAsBytesSync(), sourceBytes);
    expect(config.toJson().keys, isNot(contains('image_b64')));
    expect(config.toJson()['source_image_path'], config.sourceImagePath);
  });
}
