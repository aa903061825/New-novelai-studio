import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_assembly_application.dart';

RecastMapping mappingWithAppliedAiRoleExtraction({
  required RecastMapping mapping,
  required ScriptAiRoleExtraction extraction,
}) {
  return const ScriptAiRoleAssemblyApplication()
      .apply(
        mapping: mapping,
        extraction: extraction,
        stageLabelFor: _stageLabelForCacheTool,
      )
      .mapping;
}

String _stageLabelForCacheTool(ScriptAiExtractedStage stage, int index) {
  final label = stage.label.trim();
  if (label.isNotEmpty) {
    return label;
  }
  return '阶段 ${index + 1}';
}
