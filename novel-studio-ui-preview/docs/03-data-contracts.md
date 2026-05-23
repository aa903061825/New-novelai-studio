# 数据契约草案

这份文档描述 UI 需要的数据形状。它不是最终 Dart model，只是把预览接入真实制作时的字段边界讲清楚。

## StudioShellState

用于六区导航和全局状态。

```text
currentSection: home | assets | workbench | batch | gallery | settings
assetCount: int
draftCount: int
galleryCount: int
batchCount: int
hasLocalWorkspace: bool
isIndexReady: bool
```

来源：

- asset count 来自 `StudioAssetCatalogSummary`。
- gallery count 来自 `StudioGalleryService.loadRecords()`。
- draft / batch count 需要补齐持久化来源，不能长期写死。

## StudioAssetListItem

素材库和工作台素材抽屉共用。

```text
id: string
name: string
type: character | outfit | artistChain | recipe | tag | filterRule | reference | inspiration | lora | workflow
subtitle: string
promptPreview: string
sourceSnapshotLabel: string
status: available | missingReference | needsReview
canSendToWorkbench: bool
updatedAt: DateTime?
```

可从现有 workspace entities 映射：

- `Character`
- `Outfit`
- `ArtistChain`
- `Recipe`
- `Tag`

P1 再补：

- 过滤规则
- 参考图
- 灵感图
- LoRA 元数据
- 工作流资产

## PromptFragment

工作台 Prompt 栈条目。

```text
id: string
type: character | outfit | artistChain | recipe | tag | manual | replaceRule | referenceControl
name: string
positiveText: string
negativeText: string?
sourceAssetId: string?
sourceSnapshot: object?
order: int
enabled: bool
locked: bool
```

UI 行为：

- 可排序。
- 可禁用。
- 可查看来源。
- 可合成为 prompt preview。

需要明确合成顺序：

1. 角色 / Outfit
2. 画师串
3. 配方 / Tag
4. 手写补充
5. 替换规则
6. 过滤规则
7. Negative Prompt

## WorkbenchDraft

工作台导入导出和主页“继续创作”使用。

```text
schemaVersion: string
title: string
createdAt: DateTime
updatedAt: DateTime
fragments: PromptFragment[]
manualPrompt: string
negativePrompt: string
generationProfile: GenerationProfile
referenceControls: ReferenceControl[]
metadataPolicy: keep | erase | custom
sourceSnapshots: object[]
```

禁止包含：

- NAI Token
- 代理
- 输出目录
- 本机绝对路径，除非是可降级显示的历史快照

## GenerationProfile

工作台单张生成和批量 profile 共用。

```text
model: string
width: int
height: int
steps: int
sampler: string
scale: double
cfgRescale: double?
noiseSchedule: string?
seed: int?
negativePrompt: string
```

来源：

- `ParamConfig`
- `GlobalGenerationParams`
- 现有 generation payload 组装逻辑

## ReferenceControl

I2I、Vibe、Vibe V4、Precise Reference、Director 类控制统一抽象。

```text
id: string
kind: i2i | vibe | vibeV4 | preciseReference | director
assetRef: string?
localFileSnapshot: string?
weight: double?
enabled: bool
params: object
status: available | missing | invalid
```

UI 只需要知道可用性、类型和关键参数；具体生成 payload 仍由已有 config model 转换。

## GalleryRecord

画廊详情和送回工作台使用。

```text
id: string
title: string
imagePath: string
createdAt: DateTime
prompt: string
negativePrompt: string?
generationProfile: GenerationProfile
assetHits: StudioAssetListItem[]
metadataStatus: parsed | missing | degraded | corrupt
restorePayload: WorkbenchDraft?
favorite: bool
rating: int?
```

现有 `StudioGalleryRecord` 已有基础能力，但需要逐步补：

- 关键词筛选字段。
- metadata 解析状态。
- 素材命中。
- 降级原因。

## BatchJob

批量产线页面使用。

```text
id: string
name: string
configTreeSummary: string
selectionMode: random | sequential | probability | count | all
generationProfile: GenerationProfile
totalCount: int
completedCount: int
failedCount: int
intervalSeconds: int
jitterMinSeconds: int?
jitterMaxSeconds: int?
retry429Seconds: int?
status: draft | ready | running | paused | retrying | completed | failed
queueItems: BatchQueueItem[]
logs: BatchLogLine[]
```

重点：

- 这层是 UI view model，不要替代 CasRand 原有 Config 树结构。
- Config 树真实结构仍保留在现有 `PromptConfig` / saved config 模型中。

## BatchQueueItem

```text
id: string
index: int
promptPreview: string
status: waiting | running | completed | retrying | failed | skipped
resultRecordId: string?
errorMessage: string?
retryAt: DateTime?
```

## 错误/降级状态

所有页面都要能表达：

| 状态 | UI 表现 |
|---|---|
| loading | skeleton 或状态卡 |
| empty | 带下一步入口的空态 |
| unavailable | 不清空当前编辑，显示原因 |
| missingReference | 保留文本，标记引用缺失 |
| writeDenied | 阻止写入动作，提示检查路径 |
| networkError | 保留本地结果，允许重试 |
