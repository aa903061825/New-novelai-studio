# Novel Studio UI Preview 接入总览

## 目标

这份预览不是一个要直接嵌入 Flutter 的 WebView。它的用途是把 `docs/novel-studio-integrated-prd.md` 中的产品结构具体化，作为后续 Flutter 页面重做的视觉和信息架构蓝图。

实际接入时，应把它拆成 Flutter 原生页面、组件、主题 token 和 view model，而不是复用 `index.html`。

## 接入边界

必须保留：

- 六个用户可见一级入口：`主页 / 素材库 / 工作台 / 批量产线 / 画廊 / 设置`。
- 产品主语：本地 Prompt + 生图工作室。
- 工作台同屏闭环：素材抽屉、Prompt 装配、生成参数、结果预览。
- 素材库真实读取三源归并后的 catalog，不展示空壳。
- 画廊支持 metadata 回溯，并可送回工作台。
- 批量产线保留 CasRand 的 Config 树语义和执行控制。
- 密钥、代理、输出目录等机器相关设置只在设置页，不进入工作台导出文件。

不能做：

- 不能把预览作为生产 WebView。
- 不能只换皮旧页面而不接真实数据流。
- 不能新增普通用户可见诊断入口。
- 不能重新暴露三源迁移、Workspace 装载、底层 source loader 等内部概念。
- 不能让批量产线缩水成轻量卡片，必须保留高密度配置能力。

## 现有工程落点

当前 Flutter 工程已经有可复用的基础：

| 能力 | 已有落点 |
|---|---|
| 素材库读取与发送工作台 | `lib/ui/studio_shell/widgets/asset_library_page.dart` |
| 画廊记录与送回工作台 | `lib/ui/studio_shell/widgets/studio_gallery_page.dart` |
| 工作台素材栈摘要 | `lib/ui/studio_workbench/widgets/workbench_overview_panel.dart` |
| 工作台导入导出 | `lib/ui/studio_workbench/widgets/workbench_transfer_actions.dart` |
| 素材 catalog service | `lib/data/studio/services/studio_asset_catalog_service.dart` |
| 工作台 asset service | `lib/data/studio/services/studio_workbench_asset_service.dart` |
| 画廊 service | `lib/data/studio/services/studio_gallery_service.dart` |
| 工作台 document model | `lib/data/studio/models/workbench_document.dart` |
| 画廊 record model | `lib/data/studio/models/studio_gallery_record.dart` |
| 三源 importer | `lib/data/workspace/importers/*_importer.dart` |
| 生成 payload | `lib/data/use_cases/generate_payload_use_case.dart` |

因此接入方式应是“在已有 Studio 数据和服务上重做 shell / 页面 / 组件”，而不是另起一套数据模型。

## 建议产物

实际制作中建议新增或重构为以下 Flutter 层次：

```text
lib/ui/studio_core/
  theme/studio_tokens.dart
  theme/studio_theme.dart
  widgets/studio_button.dart
  widgets/studio_panel.dart
  widgets/studio_chip.dart
  widgets/studio_asset_tile.dart
  widgets/studio_metric_card.dart

lib/ui/studio_shell/
  widgets/studio_shell_view.dart
  view_models/studio_shell_viewmodel.dart

lib/ui/studio_home/
  widgets/studio_home_page.dart
  view_models/studio_home_viewmodel.dart

lib/ui/studio_workbench/
  widgets/studio_workbench_page.dart
  widgets/workbench_asset_drawer.dart
  widgets/prompt_composer_panel.dart
  widgets/generation_preview_panel.dart
  view_models/studio_workbench_viewmodel.dart

lib/ui/studio_batch/
  widgets/studio_batch_page.dart
  widgets/config_tree_panel.dart
  widgets/batch_queue_panel.dart
  view_models/studio_batch_viewmodel.dart
```

文件名只是建议，核心原则是把主题组件、Shell、业务页面、view model 分开，避免把整个预览堆成一个巨型 widget。

## 交付检查

第一个可验收版本至少应做到：

- 启动后进入新 Studio Shell。
- 左侧只出现六个一级入口。
- 工作台页面能显示真实素材栈和当前生成参数。
- 素材库能搜索真实 catalog，并把素材发送到工作台。
- 画廊能读取真实 records，并送回工作台。
- 批量入口仍能到达现有 CasRand 配置和执行能力。
- 设置页保留密钥、代理、输出目录，不承载日常创作流程。
