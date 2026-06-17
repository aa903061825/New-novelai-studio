import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/ui/core/widgets/editable_list_tile.dart';

import '../../../data/services/config_service.dart';

class DebugSettingsView extends StatefulWidget {
  final PayloadConfig payloadConfig = GetIt.instance<PayloadConfig>();

  DebugSettingsView({super.key});

  @override
  State<StatefulWidget> createState() => DebugSettingsViewState();
}

class DebugSettingsViewState extends State<DebugSettingsView> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckboxListTile(
            title: const Text('调试 API'),
            value: widget.payloadConfig.settings.debugApiEnabled,
            onChanged: (value) => setState(
                  () {
                    if (value == null) return;
                    widget.payloadConfig.settings.debugApiEnabled = value;
                  },
                )),
        EditableListTile(
            title: '调试 API 地址',
            currentValue: widget.payloadConfig.settings.debugApiPath,
            onEditComplete: (value) => setState(
                  () {
                    widget.payloadConfig.settings.debugApiPath = value;
                  },
                )),
        ListTile(
          title: const Text('重置欢迎弹窗版本'),
          onTap: () {
            GetIt.I<PayloadConfig>().settings.welcomeMessageVersion = '';
            // Save the config
            final config = GetIt.instance<PayloadConfig>();
            final service = GetIt.instance<ConfigService>();
            service.saveConfig(config.toJson());
          },
        )
      ],
    );
  }
}
