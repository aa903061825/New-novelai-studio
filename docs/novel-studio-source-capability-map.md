# Novel Studio 三源能力归宿确认

日期：2026-05-22

## 结论

Novel Studio 的产品主线应固定为本地 `Prompt + 生图工作室`，三源能力在产品内部归并，不向用户暴露“源迁移 / Workspace / Health / source-loader”。用户只看到六区：`主页 / 素材库 / 工作台 / 批量产线 / 画廊 / 设置`。

当前 Flutter 项目已经具备可继续推进的基础：

- `WorkspaceService`、workspace schema、三源 importer 已存在。
- `StudioShellView` 六区导航已接入真实旧服务。
- `AssetLibraryPage` 已能读取角色、Outfit、画师串、配方、Tag，并发送到工作台素材栈。
- `GenerationPageViewmodel`、`GeneratePayloadUseCase`、Vibe / Precise Reference / metadata / batch retry 仍是现阶段生成主干。
- `WorkbenchTransferService` 和 `StudioGalleryService` 已覆盖工作台导入导出与生成结果回流的基础路径。

主要缺口不是“有没有新壳”，而是以下三类能力需要继续产品化：

- 工作台还需要从“简单素材追加”升级成 KAMIA 式 block/小车/草稿/预设 + CasRand 生成参数同屏的三栏工作台。
- 批量产线需要同时承接 CasRand Config 树语义和 KAMIA NAI queue / batch plan，而不是只放旧配置页。
- 素材工具还没有真正接入画师串工作室的翻译、分类、拆分、metadata 排序与批处理能力。

## NAI CasRand

| 能力 | Novel Studio 归宿 | 当前实现状态 | 决策 |
|---|---|---|---|
| NAI Token、代理、输出目录、文件名前缀 | `设置`、`批量产线 > 生成环境` | `Settings`、`ConfigService`、生成 VM 已沿用 | 保留并重组 |
| 单张生成、停止、结果卡、Prompt 预览 | `工作台` | `GenerationPageView` 已挂到 Studio 工作台，结果卡已 Studio 化 | 保留 |
| 级联 Prompt Config 树：随机、顺序、概率、数量、全部、shuffle、顺序状态重置 | `批量产线 > Config 树编辑器` | `PromptConfig` 模型和旧 `ConfigPageView` 仍在，导航已放入批量产线 | 保留原语义 |
| Character Config 与角色正负 Prompt | `素材库 > 角色`、`工作台 > 角色栈`、批量兼容层 | 旧 `CharacterConfig` 仍参与 payload；workspace `CharacterEntry` 已存在 | 合并并保留兼容 |
| Saved Config、JSON 保存/读取 | `批量产线 > 配置方案`、`工作台导入导出` | `WorkbenchTransferService` 已支持 creative state 导出/导入 | 保留 |
| Prompt Replace Rules、变量替换、覆盖 Prompt | `工作台 > Prompt 处理`、`批量产线 > 配置规则` | `PromptTabViewmodel`、`GeneratePayloadUseCase` 已覆盖分组替换与变量替换 | 保留 |
| 模型、尺寸、steps、sampler、scale、cfg rescale、noise schedule、seed、negative prompt | `工作台 > 生成参数`、`批量产线 > Generation Profile` | `ParamConfig`、`GlobalGenerationParams` 已覆盖 | 保留 |
| I2I、Vibe、Vibe V4、Precise Reference、Director reference | `工作台 > 参考与控制`，批量引用 Profile | 数据模型和 payload 生成逻辑仍在 | 保留 |
| 批次数量、批次间隔、抖动、429 重试、请求数、恢复 | `批量产线 > 执行控制` | `Settings`、`GenerationRuntimeState`、VM 测试已覆盖部分行为 | 保留 |
| metadata 擦除、自定义 metadata、生成历史 | `画廊 > metadata`、`设置 > 输出策略` | `ImageService`、`StudioGalleryService` 已覆盖基础写入/回流 | 保留 |

## KAMIA Prompt Studio

| 能力 | Novel Studio 归宿 | 当前实现状态 | 决策 |
|---|---|---|---|
| 8 block 体系：style / sub_style / character / clothing / action / expression / scene / camera | `素材库 > 配方/Tag`、`工作台 > Prompt block 栈` | `WorkspacePaths.blocks` 与 `KamiaImporter` 已对齐 8 block | 保留 |
| recipes、tags、中文名、分类、图示参考 | `素材库`、工作台素材抽屉 | importer 已导入 recipes/tags；素材库可搜索和发送 | 保留 |
| 角色、Outfit、8 视角构图变体 | `素材库 > 角色/Outfit`、`工作台 > 角色栈` | `ViewVariantTexts` 已存在；导入和 asset catalog 已覆盖基础路径 | 保留 |
| 小车 Cart、block relation：and / or / blend / schedule | `工作台 > Prompt 装配` | 当前 Flutter 只有简单 append，尚未表达 relation | 合并，作为工作台 P0 细项 |
| 组装棚 Assembly、`BREAK` 分隔、隐私 block 占位 | `工作台 > 结构化 Prompt 预览` | Flutter 还未原生承接 KAMIA assembly；secret 规则已有设计约束 | 合并，隐私内容内部化 |
| Prompt 草稿、历史、预设 | `工作台 > 草稿与预设`、`production/assembly_presets` | workspace 目录已预留，但服务/页面未落地 | 保留 |
| 灵感库、参考图、图片素材 | `素材库 > 灵感/参考`、`画廊 > 引用` | workspace 目录有 `inspirations`，当前 importer/service 未完整接入 | 保留，P1 补齐 |
| LoRA 元数据、触发词、权重 | `素材库 > LoRA 资产`、`批量产线 > 工作流资产` | workspace 目录有 `loras`，当前 importer/service 未完整接入 | 保留为素材能力 |
| NAI queue、baseBlocks、角色位置、paramsOverride、batch plan | `批量产线 > 队列` | KAMIA 数据有 `batch_plans`，Flutter `BatchPlan` 模型存在但 importer/service 未完整接入 | 合并 |
| ComfyUI workflow、workflow importer、LoRA slots、param mapping | `批量产线 > 工作流资产` | workspace 已预留 `production/workflows`；执行能力不应进入 P0 | 资产保留，执行 P1 后置 |
| private blocks、API token、代理 | `设置` 与本地 secretRef | 不写入 workspace 的原则已在数据设计中明确 | 内部化，禁止导出 |

## 画师串工作室

| 能力 | Novel Studio 归宿 | 当前实现状态 | 决策 |
|---|---|---|---|
| 画师串、画风 Prompt、标签、参考图 | `素材库 > 画师串`、`工作台 > Artist Stack` | `ArtistChain` 与 `ArtistStudioImporter` 已覆盖基础数据；工作台可 append | 保留 |
| 角色 preset、Outfit/Prompt 组合 | `素材库 > 角色预设`、工作台角色装配 | importer 能把 `characters`、`outfit`、`presets` 转为角色与 outfits | 保留 |
| `nai_unified_config.json` 删除词、强过滤、替换规则 | `素材库 > 过滤规则`、`素材工具 > 规则编辑` | importer 可读 filterRules，但当前 workspace service 没有完整读写入口 | 保留 |
| 翻译工作室：cache、手工翻译、Google、AI 翻译 | `素材工具 > 翻译与拆分` | Flutter 尚未接入；辅助 AI 配置应只留本地设置 | 保留，P1 |
| AI Prompt 分类 | `素材工具 > 分类入栈` | Flutter 尚未接入 | 保留，P1 |
| Prompt 智能拆分、分页标签板、拖拽整理、复制 | `素材工具 > 标签整理板` | Flutter 尚未接入，当前 `StudioToolsPage` 只是摘要 | 保留，P1 |
| 单图 metadata 测试、V4 prompt/char 分离、坐标、分辨率读取 | `素材工具 > metadata 解析器`、`画廊 > metadata 详情` | Flutter 已有 NAI metadata 导入和画廊记录，但没有这套清洗视图 | 保留 |
| 文件夹批处理、排序、输出 `_SUMMARY_*`、`_COORDS` | `素材工具 > metadata 排序器` | Flutter 尚未接入 | 保留，P1 |
| 工具日志、内部 info 接口 | 内部日志/开发诊断 | 不进主导航 | 内部化 |

## 对现有任务的影响

`NAI_NEW-jkj` 完成后应解锁：

- `NAI_NEW-nt1`：工作台三栏重做。关键验收要补上 KAMIA block 顺序、Cart relation、Assembly/草稿/预设、8-view 变体选择，以及 CasRand 参数/参考控制同屏。
- `NAI_NEW-3m7`：批量产线。关键验收要补上 CasRand Config 树语义、KAMIA queue/batch plan 合并、batch result 写画廊。

继续保留的并行任务：

- `NAI_NEW-c8d`：素材库需要从当前卡片列表升级到高密度列表/详情抽屉/缺失引用提示/编辑保存。
- `NAI_NEW-802`：画廊需要补齐筛选、详情 metadata、图片预览、降级状态和回流。
- `NAI_NEW-frr`：截图/视觉验收流程仍然需要单独解决。

建议新增后续任务：

- 补齐 KAMIA 非基础资产导入：`inspirations / loras / workflows / batch_plans / assembly_presets`。
- 落地素材工具：翻译、AI 分类、标签拆分、filter rules、metadata 单图解析与文件夹批处理。
- 统一本地密钥与辅助 AI 设置边界：NAI token、代理、AI URL/key、private blocks 只能保存在本地设置或 secretRef，不写入 workspace 和导出文件。

