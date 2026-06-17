import 'package:flutter/material.dart';
import 'package:novel_studio/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/workbench_single_image_console.dart';

class GenerationPreviewPanel extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const GenerationPreviewPanel({
    super.key,
    required this.viewmodel,
  });

  @override
  Widget build(BuildContext context) {
    return WorkbenchGenerationResultsPanel(viewmodel: viewmodel);
  }
}
