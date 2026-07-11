# Novel Studio

Novel Studio 是一个面向 NovelAI 图片工作流的本地优先 Flutter 桌面应用。
它把提示词编排、素材库、剧本 Recast、画廊复核和确定性生产队列放在同一个工作台里。

Dart package 名称是 `novel_studio`，平台应用标识使用 `studio.novel.novelstudio`。

## 当前能力

- 管理角色、服装、画师串、灵感、LoRA、配方、提示词片段和工作流预设。
- 用结构化 PromptTag 工具编辑和复核 NovelAI 提示词，支持翻译缓存、过滤规则和图片元数据导入。
- 对图集剧本做 Script Recast，把源帧证据映射到可替换角色、服装、角色槽和生产计划。
- 维护确定性生产队列，并把生成图、源剧本、提示词和画廊记录关联起来。
- 导入和整理既有素材种子数据，但以当前 Novel Studio 工作区模型为主。

## 目录速览

- `lib/core/`：应用组合、全局常量和基础设施。
- `lib/data/`：工作区、素材库、生成 payload、Script Recast、导入导出和业务用例。
- `lib/ui/`：桌面端页面、ViewModel、共享 Studio 组件和交互控件。
- `assets/`：本地化、种子数据和随包资源。
- `tool/`：导入、审计、缓存修复、批处理和一次性维护脚本。
- `test/`：模型、服务、工具、ViewModel 和 Widget 回归测试。
- `docs/`：需求、设计记录、原型和验收材料。历史计划只作上下文，不一定代表当前实现。

`build/`、`.dart_tool/`、平台生成产物和本地缓存不属于源代码资产，可重新生成。

## 开发命令

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build windows
```

日常目标平台是 Windows 桌面。Android、iOS、Linux、macOS 和 Windows 目录保留 Flutter 标准平台脚手架。

## 协作流程

本仓库通常由 Codex 和 Claude 共同维护。开始任何较大改动前先看当前工作区：

```powershell
git status --short --branch
```

- 需要长期保留的设计、实施计划和验收记录统一放在 `docs/` 对应目录，不依赖本地任务工具。
- 工作区经常会有别人未提交的改动。只修改当前任务需要的文件，不要回滚不属于自己的变更。
- 对 Script Recast 缓存、翻译缓存和剧本修复，默认不得调用项目里配置的 API、Token、代理或任何凭据；除非当前聊天里明确授权。
- 历史导入器不再作为新版本入口。素材种子和已存在工作区迁移路径只有在当前功能或测试仍依赖时才保留。

## 验证建议

- 文档或配置整理：至少跑 `flutter analyze --no-pub`。
- 改 `lib/data/` 或共享模型：跑相关 `test/data/...` 用例。
- 改 `lib/ui/`：跑相关 Widget 测试，并在需要时启动 Windows 构建或本地应用验证。
- 改脚本或缓存工具：优先使用本地文件和离线验证，避免触发外部 API。
