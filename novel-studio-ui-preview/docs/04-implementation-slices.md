# 实施切片建议

这份文档把预览落地拆成能逐步验收的制作切片。它和仓库已有 `docs/superpowers/plans/2026-05-22-novel-studio-integration-roadmap.md` 对齐，但更偏 UI 接入。

## Slice 0：主题与基础组件

目标：

- 建立 `studio_core` token、theme、基础组件。
- 不改业务流，只先能渲染暗色 Studio 组件。

建议改动：

- 新增 `StudioTokens`
- 新增 `StudioTheme`
- 新增 `StudioPanel / StudioButton / StudioChip / StudioIconButton / StudioMetricCard`

验收：

- 组件能在一个 demo page 或现有页面局部使用。
- 主 CTA 是黄色。
- 卡片右下尖角。
- 中文没有斜体。

## Slice 1：Studio Shell 六区导航

目标：

- 替换用户可见的信息架构。
- 六个一级入口稳定出现。
- 旧调试/诊断类入口不在普通导航出现。

建议改动：

- 新增或重构 `StudioShellView`
- 接入 `主页 / 素材库 / 工作台 / 批量产线 / 画廊 / 设置`
- 工作台、素材库、画廊先挂现有可用页面，避免空壳

验收：

- 启动后能进入 Studio Shell。
- 每个一级入口能打开有真实数据或真实功能的页面。
- 设置页不承载工作台导入导出。

## Slice 2：素材库视觉重做

目标：

- 把现有 `AssetLibraryPage` 重做成预览中的高密度列表 + 详情抽屉。
- 保留搜索、筛选、发送到工作台。

建议改动：

- 保留 `StudioAssetCatalogService.loadSnapshot()`。
- 把 `_AssetSection` 的多段列表合并成统一表格/列表视图。
- 增加右侧详情 panel。

验收：

- 搜索真实素材可用。
- 类型筛选可用。
- 发送到工作台后 `StudioWorkbenchAssetService.fragments` 变化。
- 缺失引用时能显示警告而不是隐藏素材。

## Slice 3：工作台三栏主界面

目标：

- 落地预览的核心：左素材抽屉、中 Prompt 装配、右生成与预览。

建议改动：

- 新建 `StudioWorkbenchPage`。
- 将 `WorkbenchOverviewPanel` 的素材栈能力扩展成 `PromptComposerPanel`。
- 继续复用 `PayloadConfig`、`GenerationPageViewmodel` 和现有参数 model。
- 把 `WorkbenchTransferActions` 放回工作台工具栏。

验收：

- 从素材库发送的素材能出现在 Prompt 栈。
- Prompt preview 能根据素材和手写内容更新。
- 生成参数显示真实当前值。
- 点击生成走现有生成路径。
- 导入导出不包含 token、代理、输出目录。

## Slice 4：画廊详情与回溯

目标：

- 从现有记录列表升级为画廊网格 + metadata 详情 + 送回工作台。

建议改动：

- 保留 `StudioGalleryService.loadRecords()` 和 `restoreToWorkbench()`。
- 为 `StudioGalleryRecord` 或 view model 增加 metadata 状态、素材命中、降级原因。
- 增加筛选 UI。

验收：

- 有记录时展示结果卡。
- metadata 可读时展示 Prompt、Seed、模型、素材命中。
- metadata 缺失时降级显示文件基础信息。
- 送回工作台能恢复 Prompt 和参数。

## Slice 5：批量产线重构

目标：

- 把 CasRand 批量能力放入新信息架构，但不削弱配置树能力。

建议改动：

- 新建 `StudioBatchPage`。
- 复用现有 Prompt Config / saved config / generation runtime state。
- 增加队列和日志面板。
- 增加“从工作台预设创建批量配置”入口。

验收：

- 原有随机/顺序/概率/数量/全部选择语义可用。
- 批次数量、间隔、抖动、429 重试可见可改。
- 暂停/恢复/重试保持原行为。
- 批量结果进入画廊记录。

## Slice 6：主页和设置收口

目标：

- 主页显示最近草稿、最近结果、最近批次。
- 设置页只保留低频本地偏好。

建议改动：

- 新建 `StudioHomePage`。
- 设置页视觉迁移到 Studio theme。
- 工作台导入导出从设置路径移除。

验收：

- 首屏能回到最近创作。
- 最近项失效时降级，不阻塞其他入口。
- 设置页可保存 token、代理、输出目录、主题、语言。
- 诊断类能力不作为普通页面入口出现。

## Slice 7：视觉与回归

目标：

- 统一视觉语言，补全空/加载/错误态，回归旧能力。

检查清单：

- 工作台 1440 宽三栏可用。
- 1180 宽无明显文本挤压。
- 窄窗口可堆叠。
- 素材、工作台、批量、画廊都有真实数据流。
- 生成参数、I2I、Vibe、Vibe V4、Precise Reference、metadata 策略未丢失。
- 旧 CasRand 生成和批量测试通过。
- 新 Studio 页面 Widget tests 覆盖导航、素材发送、导入导出、画廊回流。

## 推荐测试

| 层级 | 测试 |
|---|---|
| unit | Prompt fragment 合成顺序、workbench document 不含私密字段 |
| unit | Gallery record restore 到 `PayloadConfig` |
| widget | 六区导航切换 |
| widget | 素材库搜索/筛选/发送工作台 |
| widget | 工作台 Prompt 栈更新 |
| widget | 画廊 metadata 降级状态 |
| integration | 从素材库到工作台生成，再写入画廊并回流 |
| regression | 原 CasRand batch config 执行语义 |
