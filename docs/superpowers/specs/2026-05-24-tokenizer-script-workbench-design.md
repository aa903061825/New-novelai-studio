# 分词剧本工作台设计

日期：2026-05-24

## 背景

旧工具 `E:\NAI的脚本群\分词器.py` 是一个为“快速可用”服务的独立分词控制台。它可以解析 NovelAI metadata、拆分 v4 prompt 的场景和角色、应用删除词/强过滤/替换规则、提取坐标和分辨率、对单图做 AI 分类，并把一个文件夹批量整理成 `_SUMMARY_*`、`_COORDS`、`_RESOLUTIONS` 等文本文件。

这些能力对当前项目仍然重要，但旧工具的输出方式偏临时：一张图主要依赖一行文本、换行符、竖线和文件名来表达关系。新项目需要把它升级成正式的批量结构化工作流，而不是把 Python UI 原样搬进 Flutter。

旧的 Novel Studio PRD 和六区导航只能作为历史参考。当前设计以用户本轮确认的“分词剧本”为准，可以调整一级导航和模块边界。

## 模块定位

`分词剧本` 是一个一级工作台。

它负责把一个文件夹中的图片或 JSON 解析成可校验、可替换、可保存、可发送到生产线的结构化批量任务。

它不负责真正执行生图。执行仍由 `生产线` 承担。

建议一级导航调整为：

- 主页
- 素材库
- 创作工作台
- 分词剧本
- 生产线
- 画廊
- 设置

职责边界：

| 模块 | 职责 |
|---|---|
| 分词剧本 | 解析已有图片/JSON，生成结构化任务、占位符和剧本 |
| 生产线 | 执行一图一任务的批量生成、重试、队列和回流 |
| 创作工作台 | 单张图创作、Prompt 装配、参数调试 |
| 素材库 | 长期保存角色、画师串、服装部件、分类知识 |
| 画廊 | 结果浏览、metadata 回溯、再次创作 |

## 核心目标

- 选择一个文件夹后，自动解析其中的图片或 JSON。
- 自动抽取样本，让用户校验关键识别结果。
- 将画师串、角色身份、角色部件从 prompt 中结构化出来。
- 生成可替换占位符，例如 `[画师串]`、`[巫恋]`、`[巫恋上装]`。
- 支持角色在不同图片中的位置互换，不把 `char1` 固定等同于某个角色。
- 支持自然语言 prompt，通过 AI 解析并保留自然语言结构。
- 每个剧本保存为可重复调用的任务方案。
- 用户确认过的分类知识沉淀到长期知识库。
- 处理完成后一图一任务发送到生产线，且每条任务仍可调整。

## 非目标

- 不原样复刻 `customtkinter` 分词器 UI。
- 不继续把 `_SUMMARY_*` 文本作为内部主格式。
- 不把自然语言强制转换成 tag 串。
- 不让动作类内容默认占位符化。
- 不把 AI 未确认的推断直接写入长期知识库。
- 不把分词剧本当成通用模板强行套给其他文件夹。

## 当前可复用能力

当前 Flutter 项目已经存在部分底层能力，可优先复用：

| 能力 | 现有位置 | 用法 |
|---|---|---|
| NAI metadata 解析 | `lib/data/studio/tools/nai_metadata_parser.dart` | 解析图片/JSON中的 prompt、参数、v4 caption、坐标、分辨率 |
| metadata 批处理 | `lib/data/studio/tools/nai_metadata_batch_processor.dart` | 现有 `_SUMMARY_*` 兼容输出基础 |
| tag 过滤与分桶 | `lib/data/studio/tools/prompt_tag_processor.dart` | 删除词、强过滤、替换规则、启发式分桶 |
| 过滤规则模型 | `lib/data/studio/tools/filter_rule_config.dart` | 承载删除词、强过滤、替换规则、权重保留等设置 |
| 在线 AI/翻译接口抽象 | `lib/data/studio/tools/online_ai_tools.dart` | 后续接 AI 分类和自然语言解析 |
| 翻译缓存 | `lib/data/studio/tools/translation_cache.dart` | 后续给知识库或标签翻译复用 |
| 工作台 metadata 导入 | `lib/data/studio/services/workbench_metadata_import_service.dart` | 可复用 PNG/文本 metadata 读取路径 |

缺口主要在正式工作流、数据结构、校验、剧本保存、知识库沉淀和生产线交接。

## 核心对象

### 分词剧本

代表一个文件夹/一批文件的完整处理方案。

字段建议：

```text
scriptId
name
sourceFolder
sourceMode: auto | image | json
createdAt
updatedAt
status: scanning | needsReview | ready | sent | archived
sourceFiles[]
sampleFileIds[]
globalArtistPlaceholder: "[画师串]"
characterIdentities[]
styleStages[]
knowledgeCandidates[]
imageTasks[]
pipelineExportConfig
legacyExportConfig
knowledgeSnapshot
exportPolicy
```

它的重点是复现这批文件如何被处理，而不是作为通用模板套给其他文件夹。

剧本保存时同时保留当时使用的知识库快照和“用最新知识库重新解析”的入口。默认重跑使用快照以保证复现；用户主动选择时才用最新知识库改进结果。

剧本也支持导出/导入独立文件。导出默认不打包源图片/JSON，只保存路径、文件名、hash/修改时间、最终 prompt、必要映射、生成参数、知识库快照和生产线配置。用户可以额外勾选打包源文件。导出内容不能包含 API key、proxy、token 等本地秘密。

### 图片任务

一张源图或一个源 JSON 对应一条任务。

字段建议：

```text
taskId
sourceFile
sourceKind: image | json
parseStatus
originalMetadata
originalPrompt
promptMode: tag | naturalLanguage | mixed
parsedPrompt
finalPrompt
artistEvidence[]
characterSlotMatches[]
resolution
coords
generationParams
confidence
warnings[]
reviewStatus: auto | needsReview | confirmed | adjusted
placeholderMappings[]
styleStageRefs[]
```

生产线接收的是一图一任务，而不是一个粗糙的纯文本列表。

图片任务以最终 prompt 和必要映射为主，不默认保存完整原始 prompt 或完整 metadata 大对象。源文件存在时可以重新解析；源文件缺失时仍可继续使用最终 prompt 和生成参数，但不能重新解析或查看原始 prompt。

### 角色身份

角色身份与画面位置分离。

同一个角色可以在不同图片中出现在不同 `char_caption` 位置。

```text
identityId
displayName
placeholder
explicitNames[]
evidenceTags[]
slotsSeen[]
parts:
  identity
  upperBody
  upperClothing
  lowerBody
  lowerClothing
styleStages[]
```

例子：

```text
displayName: 巫恋
placeholder: [巫恋]
explicitNames:
  shamare (arknights)
evidenceTags:
  white hair
  red eyes
slotsSeen:
  image001 char1
  image014 char2
```

显式角色名相同默认视为同一角色，即使服装完全不同也不拆成多个角色身份。角色名需要做规范化和别名归并，例如大小写、下划线、空格、转义括号、作品名括号等写法差异应能归并到同一角色。用户确认过的别名关系沉淀到知识库。

隐式角色也可以生成身份占位符，但必须基于用户校验或 AI 确认过的强身份特征。隐式角色默认先用 `[角色A]`、`[角色B]`，如果 AI 开启则可以建议更具体名称，用户确认后替换。隐式角色跨图合并只有在 AI 或用户确认后才发生。

### 角色造型阶段

同一个角色在同一剧本里可能出现多套服装。角色身份和服装造型必须分离。

如果同一角色只有一套稳定服装，使用普通部件占位符：

```text
[澄闪]
[澄闪上身]
[澄闪上装]
[澄闪下身]
[澄闪下装]
```

如果同一角色出现明显不同服装阶段，启用造型阶段：

```text
[澄闪]
[澄闪summer flowers上装]
[澄闪summer flowers下装]
[澄闪黑裙上装]
[澄闪黑裙下装]
```

规则：

- 角色身份 `[澄闪]` 始终统一，不按造型拆。
- 上装/下装在多造型时默认按造型阶段拆。
- 上身/下身只有变化明显时才跟随造型阶段拆。
- 有明确变体/皮肤名时，默认用来源变体名，例如 `summer flowers`。
- 没有明确变体名但服装明显不同，用主要服装特征命名，例如 `黑裙`、`泳装`。
- 疑似多造型但分组不确定时进入校验。
- 造型阶段内部按每张图记录适用范围，界面可压缩展示为 `001-060, 070-081`。
- 生产线列表不额外显示造型阶段；详情里保留造型阶段来源和占位符映射。
- 用户确认后的角色别名与造型阶段关系一起沉淀进知识库。

### 解析细节

图片任务可以展开到细节层。

```text
artistStack:
  originalTags[]
  replacement: [画师串]

characters:
  [巫恋]:
    identityTags[]
    upperBodyTags[]
    upperClothingTags[]
    lowerBodyTags[]
    lowerClothingTags[]
    actionTags[]
    untouchedTags[]

sceneTags[]
naturalLanguageSegments[]
warnings[]
```

动作类如 `holding book`、`reaching toward another character` 默认保留，不生成 `[巫恋动作]`。

## 占位符规则

一个分词剧本内只有一个画师串占位符：

```text
[画师串]
```

角色占位符由用户自定义命名：

```text
[巫恋]
[巫恋上身]
[巫恋上装]
[巫恋下身]
[巫恋下装]
```

如果 prompt 里有明确角色名，例如 `shamare (arknights)`，系统可默认生成角色身份，用户可改名为中文。

如果 prompt 没有明确角色名，只有服饰和特征，则系统先生成临时身份。启用 AI 时，AI 可以根据可区分特征建议名称；不启用 AI 时使用保守名称，例如 `[角色A]`。

## Tag 串处理

Tag 串适合本地规则优先。

输入：

```text
shamare (arknights), white hair, red eyes, black dress, holding book
```

目标输出：

```text
[巫恋], [巫恋上身], [巫恋上装], holding book
```

分类口径：

| 类型 | 例子 | 是否占位符化 |
|---|---|---|
| 画师串 | `artist:foo` | 是，统一为 `[画师串]` |
| 角色身份 | `shamare (arknights)` | 是 |
| 上身相关 | `white hair`, `red eyes`, `necklace` | 是 |
| 上装/服装 | `black dress`, `white shirt`, `capelet` | 是 |
| 下身相关 | `bare legs`, `thighs` | 是 |
| 下装 | `skirt`, `pants` | 是 |
| 鞋袜靴 | `thighhighs`, `boots`, `shoes` | 是，默认归下身 |
| 发型/头饰 | `long hair`, `hair ornament`, `hat` | 是，默认归上身 |
| 饰品 | `necklace`, `earrings`, `gloves`, `belt` | 是，按位置归类 |
| 动作/互动 | `holding book`, `looking at another character` | 否 |
| 表情/眼神 | `smile`, `crying`, `looking at viewer` | 否 |
| 体型/身体特征 | `small breasts`, `wide hips`, `slender`, `pointy ears` | 否 |
| 场景/构图 | `classroom`, `close-up`, `from above` | 否，除非后续明确需要 |

分类补充：

- 角色明确时，默认尽量拆出身份、上身、上装、下身、下装。
- 某类没有内容时，不生成空占位符。
- `black dress` 这类整体服装默认归上装，必要时由用户手动改。
- 同一个 tag 最终只能进入一个类别。
- 多条分类规则同时命中时，规则列表顺序优先，用户可以通过排序控制优先级。

## 自然语言处理

自然语言默认 AI 优先，本地规则只做保守辅助。

输入：

```text
巫恋穿着黑色连衣裙，然后对另一个角色伸手
```

目标输出：

```text
[巫恋]穿着[巫恋服装]，然后对另一个角色伸手
```

设计原则：

- 保留自然语言结构。
- 不强制转换成逗号 tag。
- 只替换稳定、可复用、未来需要批量替换的部件。
- 动作和互动默认保留原文。
- AI 输出必须是结构化结果，而不是直接改写最终 prompt。

AI 返回建议格式：

```json
{
  "mode": "naturalLanguage",
  "entities": [
    {
      "type": "character",
      "name": "巫恋",
      "placeholder": "[巫恋]",
      "evidence": "巫恋"
    },
    {
      "type": "clothing",
      "owner": "巫恋",
      "slot": "outfit",
      "placeholder": "[巫恋服装]",
      "evidence": "黑色连衣裙"
    }
  ],
  "replacementPreview": "[巫恋]穿着[巫恋服装]，然后对另一个角色伸手"
}
```

AI 推断结果先进入当前剧本。只有用户确认后，才进入长期知识库。

## 样本与校验

新建剧本流程：

```text
选择文件夹
-> 选择解析来源：自动 / 图片 / JSON
-> 扫描文件
-> 自动抽样
-> 解析样本
-> 生成剧本草案
-> 用户校验或 AI 辅助校验
-> 应用到全文件夹
```

抽样默认是快速模式，但样本数可配置。有些剧本一张样本就足够，有些剧本需要更多样本。

抽样不是机械固定张数，而是差异驱动。默认目标可以很少，系统优先覆盖以下差异：

1. 角色数量变化。
2. 新角色身份出现。
3. 角色位置互换且系统不确定。
4. metadata 结构变化，例如普通 prompt、v4 prompt、有坐标、无坐标。
5. 画师串状态变化。
6. 解析置信度低。
7. 自然语言 AI 解析置信度低或结构不确定。
8. prompt 长度明显变化只作为弱信号，不能主导抽样。

如果差异超过默认样本数，先给默认样本，再提示用户是否追加样本。

需校验规则：

- 画师串识别失败默认进入校验。
- 一张图里识别到多个画师串候选时，全部合并进同一个 `[画师串]`，不额外打扰。
- 角色位置互换只有在识别不确定时进入校验。
- 自然语言不因为“是自然语言”就默认校验，只有 AI 置信度低或结构不确定时校验。
- 同一角色疑似多造型但分组不确定时必须校验。

AI 辅助和手动校验是同一个校验步骤的两种模式，不做两套割裂流程。

## 三层任务结构

分词剧本使用三层结构：

### 第一层：分词剧本卡

代表整个文件夹/整批图。

显示和承载：

- 剧本名称
- 来源文件夹
- 文件数量
- 已解析数量
- 需校验数量
- 已确认数量
- 角色身份数量
- 是否有 `[画师串]`
- 状态
- 保存剧本
- 应用到全文件夹
- 发送到生产线
- 导出旧格式

### 第二层：图片任务卡

代表单张图或单个 JSON。

显示和承载：

- 文件名和缩略图
- 原始 prompt 摘要
- 最终 prompt 预览
- 识别角色
- 画师串状态
- 置信度
- review 状态
- 单图调整入口

### 第三层：解析细节卡

代表某张图中的细粒度识别结果。

显示和承载：

- 原始 metadata
- 解析后 prompt
- 最终 prompt
- 画师串证据
- 角色身份映射
- 上身/上装/下身/下装分类
- 动作和互动保留项
- 自然语言片段替换
- 坐标、分辨率、参数
- 警告和低置信度项

UI 细节后续单独讨论，本设计只固定信息层级。

## 分词知识库

分词知识库是长期资产，不等同于分词剧本。

分词剧本偏一次批处理的复现方案。分词知识库偏跨剧本积累。

可沉淀内容：

- 画师串候选
- 角色显式名称
- 隐式角色识别特征
- 上身相关 tag
- 上装 tag
- 下身相关 tag
- 下装 tag
- 自然语言片段识别经验
- 角色别名与作品名归并
- 角色造型阶段关系
- 分类规则顺序和上下文条件

沉淀规则：

| 来源 | 是否进入知识库 |
|---|---|
| 用户手动确认 | 自动进入 |
| 用户手动修改 | 自动进入 |
| AI 推断且用户确认 | 进入 |
| AI 推断未确认 | 只保存在当前剧本 |
| 本地规则推断未确认 | 只保存在当前剧本 |
| AI 新规则建议 | 进入待确认列表，用户确认后进入 |

知识库用于提升后续剧本初始识别准确率，但不强制套用旧剧本。

知识库需要支持手动合并/拆分角色别名，也需要支持手动编辑服装和部件分类词。

分类规则支持简单上下文条件，但第一版不需要复杂规则引擎。最低要求：

- 精确词。
- 包含词。
- 组合词。
- 规则顺序。
- 命中后分类。
- 命中后是否需校验。

规则优先级：

```text
已确认知识库规则
> 当前剧本规则
> 系统默认规则
> AI 建议
```

AI 与规则冲突时按规则走，不打断扫描或批处理。AI 发现的新模式进入待确认列表，批处理后由用户统一确认是否沉淀为新规则。

## 生产线交接

处理完成后，分词剧本发送到生产线的模式是一图一任务。

每个任务保留：

- 源文件引用
- 最终 prompt
- 原始 prompt
- 分辨率
- 坐标
- 生成参数
- 角色身份和占位符映射
- 画师串占位符
- 造型阶段详情引用
- 警告

生产线中仍允许调整任务内容。分词剧本负责生成可用任务草案，不剥夺后续编辑能力。

每张任务保存自己的生成参数和尺寸/分辨率。发送到生产线后，prompt 占位符替换不影响每张任务自己的参数。

旧 `_SUMMARY_*` 文件输出只作为兼容导出，不作为内部主格式。

## 剧本导出与源文件

剧本既要能内部保存，也要能导出/导入独立文件。

默认导出不打包源图片/JSON，只保存：

- 文件名。
- 源路径。
- hash 或修改时间。
- 最终 prompt。
- 必要占位符映射。
- 每张任务的生成参数和尺寸。
- 剧本规则。
- 知识库快照。
- 生产线配置。

用户可以选择打包源图片/JSON。源文件路径用于重新解析、对照查看、校验文件是否变化、后续补打包和追溯来源。

如果导入剧本时源文件路径不存在，但剧本里有最终 prompt 和必要映射，剧本仍可继续使用，并标记源文件缺失。源文件缺失时不能重新解析，不能查看原始 prompt，也不能重新做详细校验。

## 状态模型

分词剧本状态：

| 状态 | 含义 |
|---|---|
| scanning | 正在扫描文件夹 |
| parsed | 已生成初始解析结果 |
| needsReview | 存在低置信度项或未确认样本 |
| ready | 可发送到生产线 |
| sent | 已发送到生产线 |
| archived | 已归档 |

图片任务状态：

| 状态 | 含义 |
|---|---|
| auto | 自动生成，尚未人工处理 |
| needsReview | 需要校验 |
| confirmed | 已确认 |
| adjusted | 已手动调整 |
| failed | 解析失败 |

## 风险与约束

- 自然语言解析如果没有 AI，准确率会有限；本地规则只做保守替换。
- 角色身份识别不能依赖 `char_caption` 顺序，必须允许位置互换。
- AI 结果必须可校验，不能直接污染知识库。
- 旧文本导出要保留，但不能影响新的结构化数据设计。
- 批量处理时要能追溯每条任务来自哪个源文件。
- 文件夹可能很大，扫描、抽样、解析需要异步和可中断设计；具体 UI 之后再讨论。

## 后续待讨论

- 分词剧本首页和新建按钮的具体 UI。
- 剧本卡、图片任务卡、解析细节卡的布局。
- 图片/JSON 文件选择与自动识别规则。
- AI 服务配置放在设置页还是剧本校验阶段临时配置。
- 知识库在素材库中的可见程度。
- 生产线任务卡如何展示占位符和原始来源。
- 旧 `_SUMMARY_*` 兼容导出的入口和默认开关。
