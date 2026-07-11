import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/precise_reference_config.dart';

void main() {
  test('PreciseReferenceConfig.fromJson does not normalize image bytes', () {
    const tinyPngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

    final config = PreciseReferenceConfig.fromJson({
      'image_b64': tinyPngBase64,
      'file_name': 'reference.png',
      'type': 'character',
      'strength': 0.8,
      'fidelity': 0.7,
    });

    expect(config.imageB64, tinyPngBase64);
    expect(config.fileName, 'reference.png');
    expect(config.type, 'character');
    expect(config.strength, 0.8);
    expect(config.fidelity, 0.7);
  });
}
