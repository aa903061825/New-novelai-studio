# Flutter 页面映射

## 静态预览到 Flutter 的拆分

| 预览区域 | Flutter 页面/组件建议 | 现有可复用点 |
|---|---|---|
| 左侧导航 Shell | `StudioShellView` | `lib/ui/navigation/widgets/navigation_view.dart` 可参考路由状态，但入口要改成六区 |
| 顶部操作栏 | `StudioTopBar` | 当前 AppBar 行为可拆出搜索、撤销、导入导出、生成 |
| 主页 | `StudioHomePage` | 需要新建，读取最近草稿、最近结果、最近批次 |
| 素材库 | `AssetLibraryPage` 重做视觉 | 已有 `AssetLibraryPage`、`StudioAssetCatalogService` |
| 工作台 | `StudioWorkbenchPage` | 已有 `WorkbenchOverviewPanel`、`workbench_transfer_actions`、生成页 view model |
| Prompt 装配面板 | `PromptComposerPanel` | `StudioWorkbenchAssetService.fragments`、`PayloadConfig` |
| 生成与预览面板 | `GenerationPreviewPanel` | `GenerationPageViewmodel`、`ParamConfig`、I2I/Vibe/Precise configs |
| 批量产线 | `StudioBatchPage` | 现有 `PromptConfig`、saved config、generation runtime state |
| 画廊 | `StudioGalleryPage` 重做视觉 | 已有 `StudioGalleryService`、`StudioGalleryRecord` |
| 设置 | `StudioSettingsPage` | 现有 `SettingsPageView`、`SettingsPageViewmodel` |

## 页面职责

### StudioShellView

负责：

- 维护当前一级导航。
- 提供统一暗色 Studio 布局。
- 注入各页面所需 service / view model。
- 保证诊断类能力不出现在普通导航中。

不负责：

- 不直接拼接 Prompt。
- 不直接读写素材文件。
- 不直接调用生成 API。

### StudioHomePage

负责：

- 读取最近工作台草稿。
- 显示最近生成结果和最近批次摘要。
- 提供“继续创作 / 打开画廊 / 恢复批次”入口。

第一版可以先用已有 `StudioGalleryService` 和工作台 document 记录做真实数据，批量历史如果尚未统一，可先展示“最近批次摘要”但必须来自现有 runtime/history，而不是静态假卡。

### AssetLibraryPage

负责：

- 搜索、筛选、分类展示 `StudioAssetCatalogSnapshot`。
- 打开素材详情抽屉。
- 调用 `StudioWorkbenchAssetService` 把素材送到工作台。

预览里的表格和详情抽屉可以落成：

- 宽屏：左侧列表 + 右侧详情。
- 窄屏：列表优先，详情用 bottom sheet 或 full-screen dialog。

### StudioWorkbenchPage

负责：

- 左：素材抽屉。
- 中：Prompt 装配栈、手写补充、负面词、预览。
- 右：生成参数、参考控制、任务校验、结果预览。

关键点：

- `PayloadConfig` 仍是生成 payload 的事实来源之一。
- `StudioWorkbenchAssetService.fragments` 应成为 Prompt 栈 UI 的输入。
- 手写 Prompt、素材片段、替换规则、过滤规则要有清晰合成顺序。
- 导入导出只导出创作状态，不导出 token / 代理 / 输出目录。

### StudioBatchPage

负责：

- 承接 CasRand Config 树。
- 显示批次数量、间隔、抖动、重试、分辨率列表等高密度参数。
- 显示队列、日志、暂停/恢复/重试。

关键点：

- 不要把 Config 树简化成普通卡片列表。
- 工作台预设可以作为“生成批量配置”的入口，但不能覆盖原有 CasRand 选择语义。

### StudioGalleryPage

负责：

- 读取生成记录。
- 展示图像、筛选条件、metadata 状态。
- 展示详情并允许送回工作台。

现有 `StudioGalleryPage` 已有 `restoreToWorkbench(record, payloadConfig)`，接入时重点是补详情侧栏、筛选和降级状态。

### StudioSettingsPage

负责：

- Token、代理、输出目录、主题、语言、辅助 AI 配置。
- 显示本地保存和隐私边界。

不负责：

- 不承载工作台导入导出。
- 不承载普通用户可见诊断入口。

## 推荐组件清单

| 组件 | 用途 |
|---|---|
| `StudioPanel` | 所有页面主要容器，右下尖角卡片 |
| `StudioButton` | 黄色主 CTA、暗色次按钮、描边按钮 |
| `StudioIconButton` | 顶栏工具按钮 |
| `StudioChip` | 类型、状态、筛选标签 |
| `StudioSegmentedTabs` | 素材类型/画廊筛选切换 |
| `StudioAssetTile` | 素材列表行 |
| `PromptStackItem` | Prompt 装配栈条目 |
| `GenerationMetricField` | 模型、尺寸、Steps、Scale 等参数格 |
| `GalleryResultTile` | 画廊结果卡 |
| `MetadataDetailList` | metadata 详情键值列表 |
| `BatchQueueRow` | 批量队列行 |
