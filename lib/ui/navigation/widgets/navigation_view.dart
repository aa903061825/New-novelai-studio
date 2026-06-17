import 'package:flutter/material.dart';
import 'package:novel_studio/ui/navigation/view_models/navigation_view_model.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_shell_view.dart';

class NavigationView extends StatelessWidget {
  final NavigationViewModel viewModel;

  const NavigationView({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return StudioShellView(viewModel: viewModel);
  }
}
