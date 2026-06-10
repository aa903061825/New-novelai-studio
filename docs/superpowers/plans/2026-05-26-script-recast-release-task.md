# 剧本 Recast 发布任务书

> 目标：把当前“后端地基已验证”的实现推进到可实际本机验收、可发布的完整版。不要把已有 mock UI 当成完成品。

## 0. 当前验收结论

本仓库当前已经有可用的后端基础，但不能按“完整版可实际测试”验收。

已独立验证通过：

- `dart analyze`：No issues found。
- `flutter test -r expanded`：346 tests passed。
- 相关 focused tests：42 tests passed。
- Beads 当前无 `open` / `in_progress` 旧任务。
- `docs/plans/2026-05-25-script-recast-prd.md` 当前仓库不存在，不要伪造。

已具备的后端地基：

- `lib/data/studio/models/script_recast.dart`
- `lib/data/studio/models/production_task.dart`
- `lib/data/studio/services/script_recast_parser_service.dart`
- `lib/data/studio/services/script_recast_engine.dart`
- `lib/data/studio/services/script_recast_production_service.dart`
- `lib/data/studio/services/production_queue_service.dart`
- `lib/data/studio/services/production_executor_service.dart`
- `CharacterEntry` / `ArtistChain` 已扩展 Recast 所需字段。
- deterministic production plan 与 legacy batch plan 已分离。
- service 层已有失败隔离、retry failed、single-frame rerun 能力。

未通过发布验收的阻塞点：

- `StudioScriptViewModel` 仍是 mock：没有真实选择文件夹、解析剧本、生成 mapping、调用 engine、送入 production service。
- `StudioBatchPage` 仍接 `ProductionQueueViewModel.empty()`：不会加载 workspace 里的真实 deterministic plans。
- `ProductionQueueViewModel.start/pause/resume/retryFailed/rerunTask/exportSelectedTaskJson` 仍是空动作或纯 UI 状态，没有调用 executor/queue/export。
- 未完成 `E:\NAI的脚本群\作品集\...` 四套真实剧本验收。
- 未完成真实 NAI API 出图链路验收。
- 未完成画廊 provenance 深化。

## 1. 真理源

必须优先阅读：

- `AGENTS.md`
- `docs/plans/2026-05-25-script-recast-user-requirements.md`
- `docs/plans/codex交接搞.md`
- `docs/superpowers/specs/2026-05-25-script-recast-deterministic-pipeline-design.md`
- `docs/superpowers/plans/2026-05-25-script-recast-deterministic-pipeline.md`

用户最终口径：

- 入口叫“剧本”，不是“分词剧本”。
- 项目仍是全能工作台，单图生成“工作台”必须保留。
- “批量产线”完全重做，不保留旧随机配置树作为 Recast 主路径。
- Recast 输出默认直接进入批量产线；JSON 导出只是可选副产物。
- 原剧本目录只读。
- 必须支持单帧重跑。
- 不新建平行角色卡/画师串卡模型；扩展并复用 `CharacterEntry` / `ArtistChain`。
- Recast 不走旧 `GeneratePayloadUseCase` / `PromptReplaceRule` 字符串替换链路；必须产出完整 deterministic per-frame payload。

## 2. 发布范围

本轮发布不是重新设计后端模型，而是把已有后端地基接成真实产品闭环：

```text
剧本文件夹选择
  -> parse nai_*.json
  -> 显示真实帧 / schema / warnings / roles / artist chain / diff
  -> 用户配置角色、画师串、三态策略、帧级覆盖
  -> engine 生成 deterministic per-frame payload
  -> enqueue production plan
  -> 批量产线加载真实 plan
  -> start / retry failed / single-frame rerun
  -> 保存 PNG
  -> 画廊记录 provenance
```

## 2.1 上一版需求问答补充

以下内容从上一版“分词剧本工作台”设计中提炼，必须并入新版“剧本”工作流。新版产品名不再叫“分词剧本”，但这些交互和数据决策仍然有效。

### Q1: 角色槽位等于角色身份吗？

不等于。`char_captions[0]` / `char_captions[1]` 只是画面槽位，同一个角色可能在不同帧出现在不同槽位。剧本页必须允许用户确认“槽位/锚点 -> 角色身份”的映射，不能把 `slot-0` 永久等同某个角色。

验收要求：

- 自动识别只能作为建议，必须可修改。
- 每个源槽位或内嵌角色锚点都要能选择目标 `CharacterEntry`。
- 显式角色名相同默认归并为同一角色；别名、大小写、下划线、作品名括号等写法差异应能通过用户确认归并。
- 隐式角色默认先显示为“角色A / 角色B”或等价临时名，不能黑箱决定。

### Q2: 上装、下装、身体特征这些旧设计还要吗？

要。它们不是旧 UI 装饰，而是 Recast 替换能否精细可控的核心。新版应接入现有 `CharacterEntry.traits` / `outfits`，并在 Recast 页面里让用户看到和选择角色卡、服装/造型、上身、上装、下身、下装等维度。

上一版占位符语义需要保留到新版数据模型/交互里：

- `[角色]`
- `[角色上身]`
- `[角色上装]`
- `[角色下身]`
- `[角色下装]`
- 多造型时允许 `[角色 造型名 上装]` / `[角色 造型名 下装]`

验收要求：

- 角色身份和服装造型必须分离。
- 同一角色只有一套稳定服装时，可使用默认 outfit。
- 同一角色出现多套明显服装时，需要“造型阶段”概念，并显示适用帧范围，例如 `001-060, 070-081`。
- `black dress` 这类整体服装默认可归上装，但必须允许用户手动改。
- 鞋袜、头饰、饰品需要按位置归入上身/上装/下身/下装，命中冲突时用户可调整。

### Q3: 哪些 tag 应该被替换，哪些应该保留？

上一版决策仍成立：动作、互动、表情、场景、构图默认不应该被角色占位符吞掉。Recast 的默认目标是换演员/换画风，不是改故事动作。

默认策略：

- 角色锚点、身份 tag、服装/装饰 tag：跟随目标角色卡/服装。
- 动作/互动：保留。
- 表情/眼神：保留，除非用户显式覆盖。
- 场景/构图：保留。
- 画师串/风格偏置：选择目标画师串时跟随，否则保留。
- seed：默认保留。

验收要求：

- 自动分类结果必须能在剧本页校验和修改。
- 用户改过的分类应能作为该剧本的 parser override 或等价持久配置保存。
- 不允许工具把动作类内容默认占位符化，例如 `holding book`、`looking at another character` 默认应保留。

### Q4: 时间线应该只是显示帧吗？

不是。时间线是逐帧审核和帧级覆盖入口。当前只展示 chip 且无法点击，不符合上一版和最终需求。

验收要求：

- 点击帧后切换当前预览帧，diff 随之变化。
- 帧 chip 显示 parse error / warning / 已覆盖 / 已发送 / 失败等状态。
- 支持为单帧设置 frame override。
- 支持批量选择帧范围设置覆盖，例如第 50-55 帧锁定 sampler 或改画师串。
- 有覆盖的帧必须有明确标记，并可撤销。

### Q5: “保留 / 跟随 / 覆盖”应该怎么让用户理解？

三态不是三个泛泛按钮，而是每个可控维度当前策略的显式状态。

- 保留：使用源剧本原值，Recast 不动。
- 跟随：受当前角色卡、服装、画师串、模板影响。
- 覆盖：使用用户输入或选择的新值，优先级高于源剧本和卡片。

验收要求：

- 每一项当前状态必须默认可见。
- 切到“覆盖”时立即出现对应输入控件或选择器，不要让用户再猜。
- 顶部需要批量操作，例如全部保留、全部跟随、按类别切换、套用预设。
- “发送到批量产线”之前必须能看出哪些维度会被改。

### Q6: 角色卡和画师串卡必须从哪里来？

优先复用现有素材库模型，不新建平行模型。但用户不能被迫先手写完整素材库。剧本页需要支持从源剧本反向提取候选角色卡/画师串卡，再由用户确认保存。

验收要求：

- 从源剧本提取 `anchorTags`、`identityTags`、候选服装/造型、默认坐标、aliases。
- 从源剧本提取画师 entries、权重、负向调味、风格偏置。
- 提取结果必须进入可编辑确认界面，不能直接污染长期素材库。
- 保存后写入现有 `CharacterEntry` / `ArtistChain`。

### Q7: 自然语言 prompt 怎么办？

自然语言结构要保留。不要强制转成 tag 串，也不要直接让 AI 改写最终 prompt。AI 或规则只能输出结构化建议，用户确认后才应用。

验收要求：

- 自然语言段落默认保留原句式。
- 只替换稳定、可复用、未来需要批量替换的角色/服装/画师部分。
- AI 分类或命名建议必须可审阅、可拒绝。

## 2.2 素材库、过滤屏蔽、知识库和可复用能力补充

以下是 2026-05-26 追加确认的发布范围，必须和“剧本”主流程一起完成，不能当成发布后的可选优化。

### 可复用能力清单

当前仓库已有能力要优先复用，不要重新造平行系统：

- `StudioAssetCatalogService` / 素材库页面已经能加载角色、Outfit、画师串、配方、Tag、法典等资产；剧本页应直接从这里做快捷选择和替换。
- `WorkspaceService.loadCharacters/saveCharacters`、`loadArtistChains/saveArtistChains`、`loadFilterRules/saveFilterRules` 是长期资产和过滤规则的持久化入口。
- `CharacterEntry` 已有 `outfits`、`defaultOutfitId`、`anchorTags`、`identityTags`、`conflictTags`、`defaultCenters`、`aliases`、`recastNotes`。
- `ArtistChain` 已有 `artists`、`globalNegatives`、`styleHintsWeighted`、`translations` 等结构化 Recast 字段。
- `FilterRuleConfig` 与 `PromptTagProcessor.filterTags/heuristicSplit` 已支持删除词、强过滤、替换规则、权重清理、精确匹配、删除画师 tag。
- `online_ai_tools.dart` 与 `translation_cache.dart` 可作为 AI 分类、翻译、命名建议和缓存的底层入口。
- 旧 `tokenizer_script.dart` 中的 `knowledgeCandidates`、`knowledgeSnapshot`、自然语言段落、角色细分字段可作为新版 Recast 知识/缓存设计参考，但产品入口仍叫“剧本”。

### 过滤和屏蔽必须保留

过滤/屏蔽不是旧工具附带功能，而是导入剧本后避免错误 tag、禁用词、冲突画风进入产线的必要步骤。

验收要求：

- 剧本导入和 Recast 预览必须能应用 workspace 的 filter rules：删除词、强过滤、替换规则、删除画师 tag、权重清理。
- 过滤结果必须可见：哪些 tag 被删除、被替换、被强过滤，不能静默破坏源 prompt。
- 用户可对单帧或批量帧撤销/覆盖过滤决策；确认后的分类或过滤决策可进入当前剧本缓存。
- 屏蔽逻辑要区分“从最终 payload 移除”和“仅标记风险待审核”，强过滤命中默认进入待审核或显式删除列表。
- 负向 prompt、画师串 global negatives、角色 conflict tags 也要进入冲突/屏蔽检查。
- 原剧本目录只读，过滤结果只写入 workspace 的剧本缓存、知识库或 production plan。

### 素材库打通

用户期望流程：载入剧本后，让 AI 辅助分析本剧本中的主角和配角，显示候选；随后用户可以从素材仓库里快捷替换角色、Outfit/造型、画师串。

验收要求：

- 剧本页提供“AI 分析剧本”入口，输出结构化建议，而不是直接改最终 prompt。
- AI/规则要从全剧本帧频、显式名称、锚点 tag、出场位置、服装稳定性、互动关系中区分主角、配角、临时角色。
- 页面要展示主角/配角候选列表：名称、别名、证据 tag、出现帧范围、置信度、是否已映射素材库。
- 每个候选都能快捷映射到已有 `CharacterEntry`，并可选择该角色的 `defaultOutfitId` 或具体 `WorkspaceOutfit`。
- 每个画师串候选都能快捷映射到已有 `ArtistChain`。
- 映射错误必须能修改；未确认的 AI 建议不能污染素材库。
- 支持把源剧本反向提取出的角色、Outfit、画师串保存为素材库资产，但必须经过用户确认。
- 从素材库替换后，三态策略和 diff 要立即反映：保留源值、跟随素材、或使用用户覆盖。

### 知识库和剧本缓存必须保留

已经处理过的剧本应能作为知识/缓存再次使用：既保证复现，也能让后续剧本识别越来越准。

验收要求：

- 每个已处理剧本保存一个可复现缓存：source folder fingerprint、parse result、AI 分析结果、用户确认的角色/配角分类、映射、过滤决策、三态策略、帧级 override、知识库快照。
- 再次载入同一剧本时，默认命中缓存并恢复上次确认状态；源文件变化时提示用户重新解析或沿用旧缓存。
- 长期知识库只接收用户确认过的内容：别名归并、角色身份特征、Outfit/造型阶段、tag 分类修正、过滤/屏蔽规则、画师串识别。
- 未确认 AI 猜测只保存在当前剧本候选里，不进入长期知识库。
- 知识库与素材库要互通：角色/Outfit/画师串资产可被剧本知识引用，剧本确认结果也可沉淀回素材库。
- 支持“用当前知识重新分析”和“使用本剧本缓存复现”两个入口，避免新知识破坏旧结果复现。

### 典型坑点

- 槽位不是角色身份，不能把 `char_captions[0]` 固定绑定为某个角色。
- 主角/配角是剧本级判断，不是单帧判断；单帧只提供证据。
- Outfit/造型阶段不能被简化成角色身份，否则换装剧情会被错误覆盖。
- 删除/屏蔽规则不能静默吞 tag，必须有可见记录和撤销路径。
- AI 只能给建议，最终写入素材库、知识库、production payload 的内容必须可审阅。
- 自然语言 prompt 不应被强制 tag 化；只替换稳定可复用的角色/服装/画师部分。

## 3. 必做任务拆分

### Task A: 剧本页真实接线

负责文件建议：

- `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- `lib/ui/studio_script/widgets/studio_script_page.dart`
- `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- 必要时新增小型 picker/service adapter，但不要把核心逻辑写进 widget。

验收标准：

- 点击“导入剧本文件夹”后能选择/输入目录并调用 `ScriptRecastParserService.parseDirectory`。
- UI 里的帧数、解析数、warning、角色槽、画师串、diff 都来自真实 `Script` / `ScriptFrame`。
- 支持 parsed/error frame 可见，坏帧不阻断整个剧本。
- 支持从素材库选择/替换 `CharacterEntry`、`WorkspaceOutfit`、`ArtistChain`，并在映射错误时直接修改。
- 支持 AI 分析主角/配角候选，候选必须带证据、帧范围、置信度和确认状态。
- 支持剧本缓存/知识库恢复：重新载入已处理剧本时恢复用户确认过的映射、过滤和帧级 override。
- 支持过滤/屏蔽预览：删除词、强过滤、替换规则、冲突 tag 的命中结果可见、可撤销、可覆盖。
- “发送到批量产线”调用 `ScriptRecastEngine.resolvePayloads` + `ScriptRecastProductionService.enqueueRecastResult`。
- 发送成功后可以导航到“批量产线”并看到真实 plan。
- 测试不允许只测 mock 字符串，要覆盖真实 fixture。

### Task B: 批量产线真实接线

负责文件建议：

- `lib/ui/studio_batch/view_models/production_queue_viewmodel.dart`
- `lib/ui/studio_batch/widgets/studio_batch_page.dart`
- `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- `lib/main.dart`

验收标准：

- 进入“批量产线”时从 `WorkspaceService.loadProductionPlans()` 加载真实 deterministic plans。
- `start()` 调用 `ProductionExecutorService.runPlan` 或等价真实执行路径。
- `retryFailed()` 调用 `ProductionExecutorService.retryFailed`。
- `rerunTask()` 对 script frame 调用 `ProductionExecutorService.rerunFrame`，只重跑指定帧。
- 运行状态、attempts、error、outputImagePath 会写回 workspace 并刷新 UI。
- JSON export 导出选中 task payload，不影响默认 PNG 出图路径。
- UI 不出现旧 CasRand 随机 config tree。

### Task C: 真实 NAI 出图适配

负责文件建议：

- 优先复用现有生成/image service，不要复制一套 NAI client。
- 如需新增 adapter，保持薄层：`ProductionExecutorService` 仍只消费 `Map<String, dynamic> payload`。

验收标准：

- deterministic task 的 payload 能直接请求 NAI API。
- 输出 PNG 按 `suggestedFileName` 或稳定命名保存到产线输出目录。
- 单帧失败不阻断后续帧。
- token、并发、间隔、重试、输出目录属于产线执行设置；不要暴露 NAI 高阶画质微调参数。

### Task D: 画廊 provenance

负责文件建议：

- `lib/data/studio/services/studio_gallery_service.dart`
- gallery models/widgets/test 相关文件。

验收标准：

- 每张由 Recast 产出的图能追溯：script id/name/path、recast run id、production plan id、task id、frame index、source file name、payload fingerprint、mapping fingerprint。
- 从画廊送回工作台时不丢原有 metadata 和 Recast provenance。

### Task E: 本机四套真实剧本验收

真实路径：

- `E:\NAI的脚本群\作品集\vulpisfoglia suzuran 忍冬x铃兰 BBC\`
- `E:\NAI的脚本群\作品集\Chino\`
- `E:\NAI的脚本群\作品集\1战败\`
- `E:\NAI的脚本群\作品集\ある執事のトリスビアスの物語\`

验收标准：

- 四套都能 parse，不因单帧损坏导致整套失败。
- 至少各抽 5-10 帧进入 deterministic plan。
- 原始目录没有被写入或修改。
- 能 dry-run 比对 payload fingerprint。
- 在有 token 的环境下，至少跑通一套小批量 PNG 出图。

## 4. 测试要求

必须保留并扩展现有测试：

- `test/data/studio/services/script_recast_parser_service_test.dart`
- `test/data/studio/services/script_recast_engine_test.dart`
- `test/data/studio/services/script_recast_production_service_test.dart`
- `test/data/studio/services/production_executor_service_test.dart`
- `test/ui/studio_script/studio_script_page_test.dart`
- `test/ui/studio_batch/studio_batch_page_test.dart`
- `test/ui/navigation/novel_studio_navigation_test.dart`

新增测试应覆盖：

- 剧本页真实 viewmodel 从 fixture parse 并送入产线。
- 批量页 viewmodel 加载真实 plans 并调用 executor。
- 单帧 rerun 的 UI action 到 service 调用。
- 导航中保留“工作台”，入口显示“剧本”，不显示“分词剧本”。
- 原剧本只读行为。

完成前必须运行：

```powershell
dart analyze
flutter test -r expanded
```

如果改了平台文件或真实出图 adapter，还要跑对应手工验收并记录命令/结果。

## 5. Beads 与 Git 约束

- 使用 Beads 创建/跟踪所有任务，不创建 markdown TODO 作为任务源。
- 开工前 `bd prime`。
- 把任务拆成可并行 issues，按模块 claim。
- 当前仓库是 stealth mode：不要 commit、push、PR，除非用户明确要求。
- 不使用 destructive git commands。

## 6. 可直接发给新会话的提示词

```text
你现在接手 C:\Users\admin\Downloads\NAI_NEW 的“剧本 Recast + 批量产线发布版”实施。

请先使用 Beads：运行 `bd prime`，阅读 `AGENTS.md`。本仓库任务跟踪必须用 Beads，不要创建 markdown TODO。当前是 stealth mode，不要 commit/push/PR，除非我明确要求。

请完整阅读这些真理源：
- docs/plans/2026-05-25-script-recast-user-requirements.md
- docs/plans/codex交接搞.md
- docs/superpowers/specs/2026-05-25-script-recast-deterministic-pipeline-design.md
- docs/superpowers/plans/2026-05-25-script-recast-deterministic-pipeline.md
- docs/superpowers/plans/2026-05-26-script-recast-release-task.md

重要背景：
上一轮后端地基已经有了，并且我已验收过：`dart analyze` 通过，`flutter test -r expanded` 346 个测试通过。但它不能算完整版，因为 UI 主流程还是 mock/empty：
- `StudioScriptViewModel` 没有真实导入/解析/送产线。
- `StudioBatchPage` 接的是 `ProductionQueueViewModel.empty()`，不会加载真实 deterministic plans。
- `ProductionQueueViewModel.start/pause/resume/retryFailed/rerunTask/exportSelectedTaskJson` 没有调用真实 executor/queue/export。

本轮目标不是重新做模型，而是发布级收口：
1. 剧本页真实接线：选择剧本文件夹 -> parse nai_*.json -> 显示真实帧/角色槽/画师串/三态/diff -> 调 engine -> enqueue deterministic production plan。
2. 批量产线真实接线：加载 workspace deterministic plans -> start/retry failed/single-frame rerun -> 保存状态和 outputImagePath -> UI 刷新。
3. 真实 NAI 出图 adapter：优先复用现有生成/image service，不复制 NAI client；payload 必须是 Recast engine 产出的完整 per-frame payload，不走旧 GeneratePayloadUseCase/PromptReplaceRule。
4. 画廊 provenance：记录 script/run/plan/task/frame/source/payload fingerprint/mapping fingerprint。
5. 本机验收四套真实剧本：
   - E:\NAI的脚本群\作品集\vulpisfoglia suzuran 忍冬x铃兰 BBC\
   - E:\NAI的脚本群\作品集\Chino\
   - E:\NAI的脚本群\作品集\1战败\
   - E:\NAI的脚本群\作品集\ある執事のトリスビアスの物語\

硬约束：
- 入口叫“剧本”，不是“分词剧本”。
- “工作台”单图生成必须保留。
- “批量产线”是确定性任务队列，不保留旧随机配置树作为 Recast 主路径。
- 原剧本目录只读。
- 必须支持单帧重跑。
- 不新建平行角色卡/画师串卡模型，只扩展/复用 CharacterEntry 和 ArtistChain。
- Recast 不走 GeneratePayloadUseCase / PromptReplaceRule 字符串替换链路。
- 不在 UI 暴露 NAI 高阶画质微调参数。

2026-05-26 追加要求也必须纳入发布版：
- 过滤和屏蔽功能必须保留，删除词、强过滤、替换规则、冲突 tag、负向 prompt/global negatives 的命中结果要可见、可撤销、可覆盖。
- 剧本页必须和素材库打通：载入剧本后可让 AI/规则分析主角、配角、临时角色，并显示证据、出现帧、置信度和映射状态。
- 用户可以从素材库快捷替换角色、Outfit/造型、画师串；映射错误必须能直接改。
- 已处理剧本要保存缓存/知识快照，重新载入时能恢复已确认的映射、过滤决策、三态策略和帧级 override。
- 长期知识库只接收用户确认过的内容；未确认 AI 猜测只能留在当前剧本候选里。
- 旧上装/下装/上身/下身/服装造型阶段设计必须保留，并接入 `CharacterEntry.outfits`。

请自行拆分 Beads issues，并使用多个子代理并行推进：A 剧本页接线、B 批量产线接线、C NAI 出图 adapter、D 画廊 provenance、E 真实剧本验收/测试。子代理必须声明 owned files，不能互相覆盖改动。

完成前必须 fresh 运行并报告：
`dart analyze`
`flutter test -r expanded`
以及四套真实剧本的本机验收结果。不要只给计划，直接实施到可实际测试。
```
