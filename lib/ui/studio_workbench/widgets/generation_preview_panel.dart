import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/generation_page/widgets/info_card.dart';
import 'package:nai_casrand/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart';
import 'package:nai_casrand/ui/i2i_tab/widgets/i2i_tab_view.dart';
import 'package:nai_casrand/ui/parameters_config/view_models/parameters_config_viewmodel.dart';
import 'package:nai_casrand/ui/parameters_config/widgets/parameters_conifg_view.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class GenerationPreviewPanel extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const GenerationPreviewPanel({
    super.key,
    required this.viewmodel,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: StudioPanel(
        key: const ValueKey('studio-generation-preview-panel'),
        color: StudioTokens.surface2,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: '结果'),
                Tab(text: '参数'),
                Tab(text: '参考'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _GenerationResultList(viewmodel: viewmodel),
                  ParametersConfigView(viewmodel: ParametersConfigViewmodel()),
                  I2iTabView(viewmodel: I2iTabViewmodel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenerationResultList extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const _GenerationResultList({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        final itemCount = viewmodel.commandList.length;
        if (itemCount == 0) {
          return Center(
            child: Text(
              '暂无结果',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return WaterfallFlow.builder(
          gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
            crossAxisCount: viewmodel.colNum,
          ),
          padding: const EdgeInsets.all(8),
          itemCount: itemCount,
          itemBuilder: (context, index) => InfoCard(
            command: viewmodel.commandList[itemCount - 1 - index],
          ),
        );
      },
    );
  }
}
