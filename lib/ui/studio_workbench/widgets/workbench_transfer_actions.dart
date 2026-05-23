import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';

class WorkbenchTransferActions extends StatelessWidget {
  final WorkbenchTransferViewModel viewModel;

  const WorkbenchTransferActions({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioIconButton(
          key: const ValueKey('workbench-import-action'),
          tooltip: context.tr('workbench_import'),
          onPressed: () => viewModel.importFromFile(context),
          icon: Icons.file_open_outlined,
        ),
        const SizedBox(width: 8),
        StudioIconButton(
          key: const ValueKey('workbench-export-action'),
          tooltip: context.tr('workbench_export'),
          onPressed: viewModel.exportToFile,
          icon: Icons.save_alt_outlined,
        ),
      ],
    );
  }
}
