# 剧本 Recast 与确定性产线重做设计

日期：2026-05-25

## 目标

本设计把 `NAI_NEW` 调整为一个全能 NovelAI 工作台：保留现有单图生成工作台，同时新增一条完整的“剧本 Recast -> 确定性批量产线”主流程。

剧本 Recast 的目标不是整理 prompt 文本，也不是复刻旧 CasRand 随机批量，而是让用户把一个已有 `nai_*.json` 文件夹作为完整剧本导入，替换角色卡和画师串卡，显式控制每类内容是保留、跟随还是覆盖，然后把所有帧作为确定的一图一任务发送到产线，直接生成 PNG。

验收标准以 `docs/plans/2026-05-25-script-recast-user-requirements.md` 为最高优先级，以 `docs/plans/codex交接搞.md` 为执行边界补充。本设计不推翻单图工作台，不保留旧随机批量产线的产品行为。

## 已确认决策

- 应用仍是全能工作台，单图“工作台”必须保留。
- 一级导航使用 `主页 / 素材库 / 工作台 / 剧本 / 批量产线 / 画廊 / 设置`。
- 旧“分词剧本”降级为剧本工作流里的解析和校验阶段，不再作为产品名。
- 批量产线完全重做为通用确定性任务队列，不保留旧 CasRand 随机 config 树。
- 新产线接收已经确定好的一图一任务 payload。剧本 Recast 是第一主入口，后续工作台或 prompt 列表也可以投递任务。
- 支持单帧重跑。每帧任务都能独立重试和重跑，不需要重跑整部剧本。
- 原剧本文件夹永远只读。默认不落盘新 JSON 文件夹；JSON 导出只是产线任务详情里的可选副产品。
- 测试采用两层策略：仓库内保存少量真实结构 fixture，本机完整验收读取 `E:\NAI的脚本群\作品集\...` 下的真实剧本。

## 现有改动处理

当前工作区有大量未提交改动。用户已确认以下分类方向：

### 保留

- 单图工作台：`lib/ui/generation_page/`、`lib/ui/studio_workbench/`、i2i、precise reference、vibe 紧凑控件、工作台 payload 隔离。
- 元数据地基：`NaiMetadataParser`、工作台 metadata 导入、prompt 行兼容修正。
- 设计真理源：`2026-05-25-script-recast-user-requirements.md`、`codex交接搞.md`。
- 全局文字缩放，因为 Recast 控制台信息密度很高。

### 重塑

- `TokenizerScript` 模型和服务：保留文件夹扫描、PNG metadata、自然排序、容错思路，改为真正的 `Script / ParsedFrame / RecastMapping / RecastRun`。
- 旧批量页面和服务：删除旧随机批量产品语义，重做成确定性任务队列。
- `studio_shell` 导航：保留全能工作台结构，把“分词剧本”改为“剧本”。
- `prompt_tag_processor`：作为 Recast parser 的低层 token/分隔符/权重工具，而不是产品级替换规则引擎。
- workspace 存储：从 `tokenizer_scripts` 改成 script、recast mapping、run、production task 存储。
- 素材库：继续承载角色和画师串，但 Recast 卡片字段要扩展到现有 `CharacterEntry / ArtistChain` 上。

### 旁置

- legacy codex seed 和对应转换脚本。
- prompt workshop bridge 与翻译缓存深集成。
- 素材库和主页纯展示 polish。
- legacy artist seed 先作为参考保留，等 `ArtistChain` 扩展后再显式导入。

### 不沿用

- Recast 不走旧 `GeneratePayloadUseCase` 的随机 payload / PromptReplaceRule 通道。Recast 产出完整逐帧 payload，交给确定性产线执行。

## 信息架构

### 主页

主页可以展示继续创作、最近剧本、最近产线任务，但不是本次重做的核心。

### 素材库

素材库继续保存长期角色、画师串、服装、标签和参考图。Recast 不新建平行角色卡或画师串卡，而是在现有模型上扩字段。

### 工作台

工作台保留单图生成职责：素材装配、Prompt 编排、单图参数、参考图、单图生成与结果检查。工作台不承担剧本批量配置职责。

### 剧本

剧本是新主入口，负责：

- 导入或扫描一个剧本文件夹。
- 解析 `nai_*.json`，识别 schema、角色槽、内嵌角色、画师串、负向、参数。
- 从剧本反向提取角色卡和画师串卡。
- 配置 Recast：角色替换、画师串替换、三态策略、参数覆盖、帧级覆盖、预览 diff。
- 发送到批量产线。

### 批量产线

批量产线重做为确定性任务队列，负责：

- 接收完整的一图一任务 payload。
- 显示剧本任务、帧任务、状态、输出、错误。
- 执行 API 调用、保存 PNG、记录画廊、失败重试、单帧重跑、断点续跑。
- 提供极简全局执行设置：API token、并发、请求间隔、失败重试次数、输出目录，以及用户确认需要全局化的模型/steps/sampler/scale 等。

## 核心数据模型

### Script

`Script` 表示一个剧本文件夹。

字段：

- `id`
- `name`
- `rootPath`
- `frames`
- `detectedSchema`
- `detectedRoles`
- `detectedArtistMix`
- `meta`
- `parseWarnings`

`ScriptFrame` 表示一个源帧：

- `index`
- `fileName`
- `sourcePath`
- `rawJson`
- `parsed`
- `parseStatus`
- `warnings`

`ParsedFrame` 是可写回的逻辑视图：

- `baseCaption`
- `charCaptions`
- `negativeBase`
- `negativeChars`
- `artistMix`
- `generationParams`
- `sourcePayload`

解析必须保留原始 JSON 与原始文本片段。未被 Recast 修改的片段写回时优先复用原文。

### ScriptSchema

支持：

- `v4_slotted`：角色主要在 `char_captions[]`。
- `base_inline`：角色主要在 `base_caption`。
- `v4_partial`：槽位和 base 内嵌混合。
- `unknown`：不能可靠推断，进入手工指认。

schema 通过逐帧投票得出。帧级异常不阻塞整剧。

### Prompt AST

Recast parser 在 `NaiMetadataParser` 之后新增 prompt AST 层。它负责：

- 识别普通 tag、加权组、原始片段。
- 支持 `1.5::xxx::`、`{{xxx}}`、`(xxx:1.2)`、负权重。
- 识别半角/全角逗号和冒号混用。
- 保留错别字和原写法，不自动纠错。
- 标记角色锚点、角色身份 tag、角色装饰 tag、状态 tag、场景 tag、构图 tag、动作 tag、画师串、风格偏置、NSFW 调味、质量尾、负向段。

自动分类必须允许用户在剧本解析视图里手工改归类，并持久化为该剧本的 parser override。

### 角色卡扩展

扩展现有 `CharacterEntry`，不新建 Recast 专用角色模型。

新增字段：

- `anchorTags`
- `identityTags`
- `conflictTags`
- `defaultCenters`
- `aliases`
- `recastNotes`

现有 `traits / outfits / imageRefs` 继续保留。Recast 使用 `anchorTags` 匹配源剧本里的角色，用 `identityTags` 和 outfit/tag 结构生成替换内容，用 `conflictTags` 清除源角色不兼容内容。

### 画师串扩展

扩展现有 `ArtistChain`。

新增结构：

- `artists: List<ArtistEntry>`
- `globalNegatives: List<WeightedTag>`
- `styleHintsWeighted: List<WeightedTag>`

`ArtistEntry`：

- `name`
- `prefix`
- `weight`
- `groupedWith`

旧 `tags` 和 `prompt` 可保留用于兼容和显示，但 Recast 写回优先使用结构化字段。

### RecastMapping

`RecastMapping` 表示一次 Recast 怎么做。

字段：

- `scriptId`
- `roleSwaps`
- `artistSwap`
- `segmentPolicies`
- `paramPolicies`
- `frameOverrides`
- `preservePresetId`
- `outputPolicy`

`TriStatePolicy`：

- `lock`：使用原帧内容。
- `follow`：受角色卡、画师串卡或模板影响。
- `override`：使用用户提供值。

默认值：

- 角色锚点、身份 tag、装饰 tag：`follow`
- 角色状态、场景、构图、动作、NSFW 调味、质量尾、负向 base：`lock`
- 画师串、风格偏置：按是否选择新画师串决定，选择时 `follow`，不选择时 `lock`
- seed：`lock`
- width/height、coords、use_coords、use_order：`lock`
- NAI 高阶画质参数：不进入 policy UI，始终逐帧继承。

### RecastRun

`RecastRun` 记录一次执行。

字段：

- `id`
- `scriptId`
- `mappingId`
- `productionPlanId`
- `status`
- `startedAt`
- `finishedAt`
- `frameResults`
- `configFingerprint`

`FrameResult`：

- `frameIndex`
- `sourceFileName`
- `taskId`
- `status`
- `payloadFingerprint`
- `outputImagePath`
- `error`
- `attempts`
- `lastRunAt`

每个 frame result 对应产线中的一个确定性任务，支持独立重试和重跑。

### ProductionTask

新产线的核心是确定性一图一任务。

字段：

- `id`
- `planId`
- `taskType`
- `title`
- `source`
- `frameIndex`
- `payload`
- `payloadFingerprint`
- `suggestedFileName`
- `status`
- `attempts`
- `outputImagePath`
- `error`
- `createdAt`
- `updatedAt`

`taskType` 初始支持：

- `script_recast_frame`
- `manual_single_frame`

旧随机 config 树不作为产品任务类型保留。

## 解析流程

1. 选择或拖入剧本文件夹。
2. 扫描 `nai_*.json`，按自然数字顺序排序，不硬编码文档里的帧数。
3. 对每个 JSON 调用 `NaiMetadataParser`，抽出 Description、Comment、v4 prompt、negative、coords、size、seed、steps、scale、sampler、source。
4. 对 prompt 进行 token 化和语义标记。
5. 按帧统计 schema 信号，投票得到剧本 schema。
6. 生成角色槽汇总和画师串候选。
7. 对解析失败帧标记 error 或 raw 模式，不阻塞整剧。
8. 显示剧本概览和需要确认的解析项。

## 反向提取

剧本详情页允许从源剧本另存：

- 角色卡：从角色槽或内嵌角色锚点提取 `anchorTags`、identity tags、候选装饰、默认坐标、aliases。
- 画师串卡：从 base caption 提取 artist entries、权重组、负向调味、风格偏置。

提取结果必须先进入可编辑确认界面，再保存到素材库。AI 或规则推断不能直接污染长期素材库。

## Recast 配置 UI

Recast 配置页以“剧本”为上下文，而不是通用设置页。

页面结构：

- 顶部：剧本名、帧数、schema、解析状态、主行动“发送到批量产线”。
- 角色映射区：源角色槽或锚点 -> 目标角色卡。
- 画师串区：源画师串 -> 目标画师串卡。
- 三态控制区：显示所有可控 segment 和参数。
- 帧时间线：显示帧状态、解析警告、帧级覆盖标记、单帧预览。
- diff 预览：首/中/末以及用户选中的帧，显示原 prompt 与新 prompt 差异。

三态控制必须满足：

- 默认全部可见，不放进“高级设置”。
- 每项明确显示 lock / follow / override。
- override 立即显示对应输入控件。
- 修改过的项相对默认和预设有明显标记。
- 支持一键预设和批量操作。

严禁显示：

- `sm`
- `sm_dyn`
- `cfg_rescale`
- `noise_schedule`
- `uncond_scale`
- `dynamic_thresholding`
- `controlnet_*`
- `legacy_v3_extend`
- `eta`
- `negative_momentum`
- `extra_passthrough_testing.*`

这些从原剧本逐帧继承。

## 确定性产线 UI

新批量产线不是旧 config editor。

页面结构：

- 队列总览：计划名、任务数、完成数、失败数、当前状态。
- 执行设置：API token、并发数、请求间隔、失败重试次数、输出目录。
- 任务列表：每帧一行或一张紧凑卡，显示 frame index、状态、输出缩略图、错误、重跑按钮。
- 当前任务详情：完整 payload 摘要、源剧本、源帧、Recast run、输出文件。
- 操作：开始、暂停、继续、重试失败、重跑单帧、导出本任务 JSON。

对于 Recast 任务，产线不再弹出参数配置。Recast 配置 + 产线执行设置就是完整执行上下文。

## 执行与重跑

执行时，产线按任务顺序取下一个待运行任务，直接使用任务携带的完整 payload 调 NAI API。

失败处理：

- 单帧失败记录错误和 attempts。
- 达到重试次数后标记 failed。
- 失败帧不阻塞其它帧。
- 用户可执行“重试失败”。

单帧重跑：

- 每个 frame task 都有“重跑”动作。
- 重跑使用该帧当前 resolved payload。
- 重跑不会修改源剧本，也不会重算其它帧。
- 重跑成功后追加或替换该帧输出记录，UI 必须清楚显示最新输出。

断点续跑：

- resume 必须绑定 `productionPlanId`、`recastRunId`、任务列表 fingerprint，而不是只保存完成数量。
- 如果任务列表变化，必须提示用户重新确认，不能按旧计数继续。

可重复性：

- 同一 Script + RecastMapping 生成的每帧 payload 必须稳定。
- 除时间戳和运行记录外，两次 dry transform 的 JSON/payload 应一致。

## 画廊回流

产线生成 PNG 后写入画廊记录。

画廊记录要能追溯：

- production task id
- recast run id
- script id
- frame index
- source file name
- payload fingerprint
- output image path

画廊可以送回工作台做单图再创作，但不得影响原 Recast run。

## 测试策略

### 仓库内 fixture

从真实剧本抽取少量结构样本，保存为测试 fixture。fixture 必须保留真实结构特征：

- v4 slot 角色
- base inline 角色
- 混合角色
- 画师串权重组
- negative prompt
- coords
- seed/size/sampler/source

如需保护隐私，可以裁剪内容，但不能伪造结构。

### 本机完整验收

完整验收读取：

- `E:\NAI的脚本群\作品集\vulpisfoglia suzuran 忍冬x铃兰 BBC\`
- `E:\NAI的脚本群\作品集\Chino\`
- `E:\NAI的脚本群\作品集\1战败\`
- `E:\NAI的脚本群\作品集\ある輪廻のトリスビアスの物語\`

测试不能硬编码文档帧数，必须按实际扫描结果。

### 必测场景

- 换演员：角色卡替换，场景不动，seed 不变，进入产线。
- 换画风：画师串与负向调味替换，其它保留。
- 异质剧本：v4 slotted、base inline、mixed 都能解析。
- 容错：破坏一帧 JSON 不崩溃，其它帧继续。
- 可重复性：同配置两次 transform 稳定。
- 可控保留：lock/follow/override 和帧级覆盖正确生效。
- 状态可见性：三态 UI 可见，高阶画质参数不可见。
- 产线极简：产线只显示执行设置与任务状态，不显示旧随机 config 树。
- 单帧重跑：任意完成或失败帧可独立重跑。

## 非目标

- 不做剧本自动续写。
- 不让用户写一堆字符串替换规则来模拟换角色。
- 不复制第二套产线。
- 不新建 Recast 专用角色卡或画师串卡模型。
- 不默认落盘新 JSON 文件夹。
- 不保留旧 CasRand 随机批量产品行为。
- 不把 NAI 高阶画质参数暴露在 Recast UI。

## 后续计划边界

实现计划应按可验证纵向切片拆分，但最终目标是完整版可实际测试，不以 dry-run 空壳作为完成标准。

推荐任务顺序：

1. 真实 fixture 与 parser 基线。
2. Script/ParsedFrame/Prompt AST。
3. CharacterEntry/ArtistChain Recast 字段扩展与反向提取。
4. RecastMapping 与 tri-state engine。
5. 确定性 ProductionTask/ProductionPlan。
6. 产线执行、保存、重试、单帧重跑、断点续跑。
7. 剧本 UI 与 Recast 配置 UI。
8. 产线 UI。
9. 真实全集验收。

## 自检

- 本设计保留单图工作台，没有把应用缩窄成纯剧本工具。
- 本设计把批量产线产品行为完全重做为确定性任务队列。
- 本设计没有新建平行角色卡或画师串卡模型。
- 本设计明确禁止 Recast 走旧随机 payload 通道。
- 本设计加入了单帧重跑作为核心产线能力。
- 本设计没有留下待定项或需要实现时猜测的核心产品边界。
