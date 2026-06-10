import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/i2i_config/widgets/i2i_config_view.dart';
import 'package:nai_casrand/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart';
import 'package:nai_casrand/ui/precise_reference/viewmodels/precise_reference_list_viewmodel.dart';
import 'package:nai_casrand/ui/precise_reference/widgets/precise_reference_list_view.dart';
import 'package:nai_casrand/ui/vibe_config/view_models/vibe_config_list_viewmodel.dart';
import 'package:nai_casrand/ui/vibe_config/widgets/vibe_config_list_view.dart';
import 'package:nai_casrand/ui/vibe_config_v4/viewmodels/vibe_config_v4_list_viewmodel.dart';
import 'package:nai_casrand/ui/vibe_config_v4/widgets/vibe_config_v4_list_view.dart';

class I2iTabView extends StatelessWidget {
  final I2iTabViewmodel viewmodel;
  final Widget? footer;
  final bool compact;

  const I2iTabView({
    super.key,
    required this.viewmodel,
    this.footer,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        final referenceWidget = viewmodel.isV4
            ? viewmodel.usePreciseReference
                ? PreciseReferenceListView(
                    viewmodel: PreciseReferenceListViewmodel(),
                    footer: footer,
                    compact: compact,
                  )
                : VibeConfigV4ListView(
                    viewmodel: VibeConfigV4ListViewmodel(),
                    vibeEnabled: viewmodel.vibeEnabled,
                    onVibeEnabledChanged: viewmodel.setVibeEnabled,
                    footer: footer,
                    compact: compact,
                  )
            : VibeConfigListView(
                viewmodel: VibeConfigListViewmodel(),
                vibeEnabled: viewmodel.vibeEnabled,
                onVibeEnabledChanged: viewmodel.setVibeEnabled,
                footer: footer,
                compact: compact,
              );

        final i2iConfigView = I2iConfigView(
          key: const ValueKey('workbench-i2i-config-view'),
          viewmodel: viewmodel.createI2iViewmodel(),
        );

        if (compact && !viewmodel.isV45) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              i2iConfigView,
              const Divider(height: 24),
              referenceWidget,
            ],
          );
        }

        if (!viewmodel.isV45) {
          return referenceWidget;
        }

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              i2iConfigView,
              const Divider(height: 24),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('enable_precise_reference')),
                subtitle: Text(tr('enable_precise_reference_hint')),
                secondary: const Icon(Icons.auto_fix_high_outlined),
                value: viewmodel.usePreciseReference,
                onChanged: (value) => viewmodel.setUsePreciseReference(value),
              ),
              referenceWidget,
            ],
          );
        }

        return Column(
          children: [
            SwitchListTile(
              title: Text(tr('enable_precise_reference')),
              subtitle: Text(tr('enable_precise_reference_hint')),
              secondary: const Icon(Icons.auto_fix_high_outlined),
              value: viewmodel.usePreciseReference,
              onChanged: (value) => viewmodel.setUsePreciseReference(value),
            ),
            Expanded(
              child: referenceWidget,
            ),
          ],
        );
      },
    );
  }
}
