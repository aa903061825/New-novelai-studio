import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/ui/studio_script/view_models/studio_script_viewmodel.dart';

void main() {
  test(
    'large exhibition handoff does not rescan every caption for every source term',
    () async {
      const frameCount = 240;
      const termCount = 120;
      final termTexts = [
        for (var index = 0; index < termCount; index += 1) 'role_tag_$index',
      ];
      final roleCaption = termTexts.join(', ');
      final frames = [
        for (var index = 1; index <= frameCount; index += 1)
          ScriptFrame(
            index: index,
            fileName: 'frame-$index.json',
            sourcePath: 'large-handoff/frame-$index.json',
            rawJson: '{}',
            parsed: ParsedFrame(
              baseCaption: 'scene_tag_${index % 8}, cinematic lighting',
              charCaptions: [roleCaption, 'other character, background'],
            ),
            detectedSchema: ScriptSchema.baseInline,
            parseStatus: ScriptFrameParseStatus.parsed,
          ),
      ];
      final script = Script(
        id: 'large-exhibition-handoff',
        name: 'Large Exhibition Handoff',
        rootPath: 'large-exhibition-handoff',
        frames: frames,
        detectedSchema: ScriptSchema.baseInline,
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: 'large-exhibition-handoff-fingerprint',
        updatedAt: DateTime.utc(2026, 7, 13),
        mapping: RecastMapping(
          id: 'mapping-${script.id}',
          scriptId: script.id,
          rolePromptReplacements: [
            ScriptRolePromptReplacement(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role 1',
              rules: [
                for (var index = 0; index < termCount; index += 1)
                  ScriptPromptReplacementRule(
                    id: 'rule-$index',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'mapping-term-$index',
                        text: termTexts[index],
                        category: PromptTagCategory.upperClothing,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
        aiRoleExtraction: ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Role 1',
              promptTerms: [
                for (var index = 0; index < termCount; index += 1)
                  ScriptAiExtractedPromptTerm(
                    id: 'extraction-term-$index',
                    text: termTexts[index],
                    category: PromptTagCategory.upperClothing,
                  ),
              ],
            ),
          ],
        ),
      );
      final viewModel = StudioScriptViewModel(
        restoreRecastCacheSnapshotByScriptId: ({
          required String scriptId,
          String? importPath,
        }) async =>
            RecastScriptCacheSnapshotRestore(
          cache: cache,
          script: script,
        ),
      );

      final stopwatch = Stopwatch()..start();
      await viewModel.openScriptFromExhibition(
        scriptId: script.id,
        sourceFolder: script.rootPath,
      );
      stopwatch.stop();
      viewModel.dispose();

      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 3)),
        reason: 'Source-term repair should index captions once instead of '
            'splitting them again for every extraction and mapping term.',
      );
      expect(
        viewModel.aiRoleExtraction.roles.single.promptTerms.first.frameIndexes,
        List<int>.generate(frameCount, (index) => index + 1),
      );
      expect(
        viewModel.roleReplacementMappings.single.rules.first.sourceTerms.single
            .frameIndexes,
        List<int>.generate(frameCount, (index) => index + 1),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
