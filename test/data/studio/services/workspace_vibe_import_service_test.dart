import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:novel_studio/data/studio/services/workspace_vibe_import_service.dart';

void main() {
  test('workspaceVibeReferenceForConfig preserves V4 info extracted', () {
    final config = VibeConfigV4(
      fileName: 'soft.naiv4vibe',
      vibeB64: 'encoded-vibe',
      infoExtracted: 0.24,
      referenceStrength: 0.36,
    );

    final reference = workspaceVibeReferenceForConfig(0, config);

    expect(reference.name, 'soft.naiv4vibe');
    expect(reference.vibeB64, 'encoded-vibe');
    expect(reference.infoExtracted, 0.24);
    expect(reference.referenceStrength, 0.36);
  });
}
