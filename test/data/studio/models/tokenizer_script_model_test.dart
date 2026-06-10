import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';

void main() {
  test('round trips custom category names', () {
    final now = DateTime.parse('2026-06-04T10:00:00Z');
    final script = TokenizerScript(
      scriptId: 'script-1',
      name: '雨夜档案',
      sourceFolder: r'C:\stories\rain',
      sourceMode: TokenizerScriptSourceMode.auto,
      createdAt: now,
      updatedAt: now,
      status: TokenizerScriptStatus.ready,
      sourceFiles: const [],
      sampleFileIds: const [],
      characterIdentities: const [],
      styleStages: const [],
      knowledgeCandidates: const [],
      imageTasks: const [],
      categoryNames: const ['收藏馆区', '待复查'],
      exhibitionVersionLabels: const {
        'gallery': '精选收纳',
      },
    );

    final restored = TokenizerScript.fromJson(script.toJson());

    expect(restored.categoryNames, ['收藏馆区', '待复查']);
    expect(restored.toJson()['categoryNames'], ['收藏馆区', '待复查']);
    expect(restored.exhibitionVersionLabels, {'gallery': '精选收纳'});
    expect(restored.toJson()['exhibitionVersionLabels'], {
      'gallery': '精选收纳',
    });
  });
}
