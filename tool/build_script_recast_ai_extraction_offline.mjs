import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  'build',
  'script_recast_rebuild_20260612',
  'active_cache_source_import_260_blocked_by_ai',
);
const defaultOutputDir = path.join(
  'build',
  'script_recast_rebuild_20260612',
  'offline_ai_rebuild_cache',
);
const defaultTranslationCache =
  'E:/NAI\u7684\u811a\u672c\u7fa4/trans_cache.json';
const defaultClassificationCache =
  'E:/NAI\u7684\u811a\u672c\u7fa4/tag_classification_cache.json';

const genericIdentityMap = {
  '1girl': { tag: 'girl', zh: '女孩' },
  '2girls': { tag: 'girl', zh: '女孩' },
  girl: { tag: 'girl', zh: '女孩' },
  girls: { tag: 'girl', zh: '女孩' },
  loli: { tag: 'loli', zh: '萝莉' },
  woman: { tag: 'woman', zh: '女性' },
  female: { tag: 'female', zh: '女性' },
  '1boy': { tag: 'boy', zh: '男孩' },
  boy: { tag: 'boy', zh: '男孩' },
  boys: { tag: 'boy', zh: '男孩' },
  man: { tag: 'man', zh: '男性' },
  male: { tag: 'male', zh: '男性' },
  child: { tag: 'child', zh: '儿童' },
  'fat man': { tag: 'fat man', zh: '胖男人' },
  'big man': { tag: 'big man', zh: '\u9ad8\u5927\u7537\u4eba' },
  'old man': { tag: 'old man', zh: '\u8001\u7537\u4eba' },
  'mature man': { tag: 'mature man', zh: '\u6210\u719f\u7537\u6027' },
  'rugged man': { tag: 'rugged man', zh: '\u7c97\u72b7\u7537\u6027' },
  'bald man': { tag: 'bald man', zh: '\u5149\u5934\u7537\u4eba' },
  'bald head': { tag: 'bald head', zh: '\u5149\u5934' },
  african: { tag: 'african', zh: '\u975e\u6d32\u4eba' },
  'black man': { tag: 'black man', zh: '\u9ed1\u4eba\u7537\u6027' },
  'black skinned male': { tag: 'black skinned male', zh: '\u9ed1\u8272\u76ae\u80a4\u7537\u6027' },
  'faceless male': { tag: 'faceless male', zh: '无脸男性' },
  faceless_male: { tag: 'faceless_male', zh: '无脸男性' },
  'dark skinned male': { tag: 'dark-skinned male', zh: '深色皮肤男性' },
  'dark-skinned male': { tag: 'dark-skinned male', zh: '深色皮肤男性' },
  'muscular male': { tag: 'muscular male', zh: '肌肉男性' },
  'musclar male': { tag: 'musclar male', zh: '肌肉男性' },
  'male focus': { tag: 'male focus', zh: '\u7537\u6027\u4e3b\u4f53' },
  'black male': { tag: 'black male', zh: '\u9ed1\u4eba\u7537\u6027' },
  'full body of man': { tag: 'man', zh: '\u7537\u6027' },
  'obese fat man from neck down': { tag: 'fat man', zh: '\u80a5\u80d6\u7537\u4eba' },
  'dirty fat ugly man': { tag: 'fat man', zh: '\u80a5\u80d6\u7537\u4eba' },
  'a black bald naked man': { tag: 'bald man', zh: '\u5149\u5934\u7537\u4eba' },
  goblin: { tag: 'goblin', zh: '\u54e5\u5e03\u6797' },
  monster: { tag: 'monster', zh: '\u602a\u7269' },
  'tentacle monster': { tag: 'tentacle monster', zh: '\u89e6\u624b\u602a' },
  'octopus tentacle monster': {
    tag: 'octopus tentacle monster',
    zh: '\u7ae0\u9c7c\u89e6\u624b\u602a',
  },
  'ugly octopus tentacle monster': {
    tag: 'ugly octopus tentacle monster',
    zh: '\u4e11\u964b\u7ae0\u9c7c\u89e6\u624b\u602a',
  },
  student: { tag: 'student', zh: '学生' },
  thief: { tag: 'thief', zh: '小偷' },
  bandit: { tag: 'bandit', zh: '\u5f3a\u76d7' },
  orc: { tag: 'orc', zh: '\u517d\u4eba' },
  'giant orc': { tag: 'giant orc', zh: '\u9ad8\u5927\u517d\u4eba' },
  'homeless man': { tag: 'homeless man', zh: '\u6d41\u6d6a\u7537\u4eba' },
  'homless man': { tag: 'homless man', zh: '\u6d41\u6d6a\u7537\u4eba' },
};

genericIdentityMap.shota = { tag: 'shota', zh: '\u6b63\u592a' };

const knownTermTranslations = {
  workshop: '车间',
  factory: '工厂',
  garage: '车库',
  mechanic: '机械师',
  overalls: '工装裤',
  'blue overalls': '蓝色工装',
  'black overalls': '黑色工装',
  nude: '裸体',
  naked: '裸体',
  'completely nude': '全裸',
  'school uniform': '校服',
  'sailor uniform': '水手服',
  swimsuit: '泳装',
  bikini: '比基尼',
  maid: '女仆装',
  kimono: '和服',
  yukata: '浴衣',
  'hooded jacket': '连帽夹克',
  jacket: '夹克',
  hoodie: '连帽衫',
  hood: '兜帽',
  bathroom: '浴室',
  onsen: '温泉',
  'hot spring': '温泉',
  train: '电车',
  'no humans': '无人',
  'dark skinned male': '深色皮肤男性',
  'dark-skinned male': '深色皮肤男性',
  'faceless male': '无脸男性',
  'itsuka shido date a live': '五河士道（约会大作战）',
  'itsuka shido': '五河士道',
  'rei princess connect': '怜（公主连结）',
  'yatogimi tohka date a live': '夜刀神十香（约会大作战）',
  'yatogami tohka date a live': '夜刀神十香（约会大作战）',
  'ako blue archive': '亚子（碧蓝档案）',
  'aragaki ayase': '新垣绫濑',
  'arona blue archive': '阿洛娜（碧蓝档案）',
  'asaba harumasa': '浅羽悠真',
  'aventurine honkai star rail': '砂金（崩坏：星穹铁道）',
  'belfast azur lane': '贝尔法斯特（碧蓝航线）',
  'belle zenless zone zero': '铃（绝区零）',
  'bremerton scorching hot training azur lane': '布莱默顿（炽热训练）（碧蓝航线）',
  'belfast': '贝尔法斯特',
  'bremerton': '布莱默顿',
  'doctor arknights': '博士（明日方舟）',
  'emiya shirou': '卫宫士郎',
  'eriko princess connect': '惠理子（公主连结）',
  'formidable azur lane': '可畏（碧蓝航线）',
  'fujimaru ritsuka female': '藤丸立香（女）',
  'gavial arknights': '嘉维尔（明日方舟）',
  'hakui koyori 1st costume': '博衣小夜璃（初始服装）',
  'hina blue archive': '日奈（碧蓝档案）',
  'hoshikawa sara 1st costume': '星川莎拉（初始服装）',
  'hoshimachi suisei 1st costume': '星街彗星（初始服装）',
  'hoshimi miyabi': '星见雅',
  'hoshino blue archive': '星野（碧蓝档案）',
  'hoshino first year blue archive': '星野（一年级）（碧蓝档案）',
  'ibuki blue archive': '伊吹（碧蓝档案）',
  'iori blue archive': '伊织（碧蓝档案）',
  'iroha blue archive': '伊吕波（碧蓝档案）',
  'javelin azur lane': '标枪（碧蓝航线）',
  'karyl summer princess connect': '凯露（夏日）（公主连结）',
  'keqing genshin impact': '刻晴（原神）',
  'kirima syaro': '桐间纱路',
  'kousaka kirino': '高坂桐乃',
  'kurugaya yuiko': '来谷唯湖',
  'kyoka princess connect': '镜华（公主连结）',
  'laffey azur lane': '拉菲（碧蓝航线）',
  'lyn fire emblem': '琳（火焰之纹章）',
  'march 7th honkai star rail': '三月七（崩坏：星穹铁道）',
  'mari idol blue archive': '玛丽（偶像）（碧蓝档案）',
  'mimi princess connect': '美美（公主连结）',
  'misogi princess connect': '未奏希（公主连结）',
  'mona genshin impact': '莫娜（原神）',
  'nakano nino': '中野二乃',
  'nanashi mumei emo': '七诗无名（emo）',
  'natsuki subaru': '菜月昴',
  'nishikigi chisato': '锦木千束',
  'nishizumi maho': '西住真穗',
  'nishizumi miho': '西住美穗',
  'nonomi blue archive': '野宫（碧蓝档案）',
  'otonose kanade 1st costume': '音乃濑奏（初始服装）',
  'pekomama': '佩克妈妈',
  'projekt red arknights': '红（明日方舟）',
  'ram re zero': '拉姆（Re:从零开始）',
  'rosa arknights': '早露（明日方舟）',
  'saber fate': '阿尔托莉雅（Fate）',
  'saki blue archive': '咲（碧蓝档案）',
  'sakura miko 1st costume': '樱巫女（初始服装）',
  'saren summer princess connect': '咲恋（夏日）（公主连结）',
  'saten ruiko': '佐天泪子',
  'sensei blue archive': '老师（碧蓝档案）',
  'serika blue archive': '芹香（碧蓝档案）',
  'shinosawa hiro': '篠泽广',
  'shirakami fubuki 1st costume': '白上吹雪（初始服装）',
  'shirakami fubuki': '白上吹雪',
  'sparkle honkai star rail': '花火（崩坏：星穹铁道）',
  'taihou enraptured companion azur lane': '大凤（恋慕伴侣）（碧蓝航线）',
  'tokino sora 1st costume': '时乃空（初始服装）',
  'tokino sora': '时乃空',
  'tokoyami towa jirai kei': '常暗永远（地雷系）',
  'tribbie honkai star rail': '缇宝（崩坏：星穹铁道）',
  'tsukishiro yanagi': '月城柳',
  'wise zenless zone zero': '哲（绝区零）',
  'yume blue archive': '梦（碧蓝档案）',
  'yuni princess connect': '优妮（公主连结）',
  'yuuki sakuna': '结城咲奈',
  'zima arknights': '凛冬（明日方舟）',
};

const options = parseArgs(process.argv.slice(2));
Object.assign(knownTermTranslations, {
  'aoi mechanic princess connect': '碧（机械师）（公主连结）',
  'aoi princess connect': '碧（公主连结）',
  'kokkoro summer princess connect': '可可萝（夏日）（公主连结）',
  'kokkoro ceremonial princess connect': '可可萝（典礼装）（公主连结）',
  'kokkoro princess connect': '可可萝（公主连结）',
  'karyl summer princess connect': '凯露（夏日）（公主连结）',
  'karyl princess connect': '凯露（公主连结）',
  'pecorine summer princess connect': '佩可莉姆（夏日）（公主连结）',
  'pecorine princess connect': '佩可莉姆（公主连结）',
  'saren princess connect': '咲恋（公主连结）',
  'saren summer princess connect': '咲恋（夏日）（公主连结）',
  'suzumi tamao': '凉美玉绪',
  'yuuki princess connect': '佑树（公主连结）',
  bikini: '\u6bd4\u57fa\u5c3c',
  swimsuit: '\u6cf3\u88c5',
  'white bikini': '\u767d\u8272\u6bd4\u57fa\u5c3c',
  'pink bikini': '\u7c89\u8272\u6bd4\u57fa\u5c3c',
  'black bikini': '\u9ed1\u8272\u6bd4\u57fa\u5c3c',
  'bikini bottom': '\u6bd4\u57fa\u5c3c\u4e0b\u88c5',
  'bikini bottom only': '\u4ec5\u6bd4\u57fa\u5c3c\u4e0b\u88c5',
  'side tie bikini bottom': '\u4fa7\u7cfb\u5e26\u6bd4\u57fa\u5c3c\u4e0b\u88c5',
  'side-tie bikini bottom': '\u4fa7\u7cfb\u5e26\u6bd4\u57fa\u5c3c\u4e0b\u88c5',
  'crop top overhang': '\u77ed\u6b3e\u4e0a\u8863',
  'cropped shirt': '\u77ed\u6b3e\u886c\u886b',
  'tennis uniform': '\u7f51\u7403\u670d',
  'two tone shirt': '\u53cc\u8272\u4e0a\u8863',
  'two-tone shirt': '\u53cc\u8272\u4e0a\u8863',
  'two tone skirt': '\u53cc\u8272\u88d9',
  'two-tone skirt': '\u53cc\u8272\u88d9',
  sneakers: '\u8fd0\u52a8\u978b',
  'red buruma': '\u7ea2\u8272\u8fd0\u52a8\u77ed\u88e4',
  buruma: '\u8fd0\u52a8\u77ed\u88e4',
  fundoshi: '\u515c\u88c6\u5e03',
  'gym shirt': '\u8fd0\u52a8\u886b',
  'white shirt': '\u767d\u886c\u886b',
  'tank top': '\u80cc\u5fc3',
  'black shorts': '\u9ed1\u8272\u77ed\u88e4',
  'dolphin shorts': '\u6d77\u8c5a\u77ed\u88e4',
  'black thighhighs': '\u9ed1\u8272\u8fc7\u819d\u889c',
  'black pantyhose': '\u9ed1\u8272\u8fde\u88e4\u889c',
  serafuku: '\u6c34\u624b\u670d',
  'school uniform': '\u6821\u670d',
  'maid uniform': '\u5973\u4ec6\u88c5',
  'bunny suit': '\u5154\u5973\u90ce\u88c5',
  'black bunny suit': '\u9ed1\u8272\u5154\u5973\u90ce\u88c5',
  'disheveled bunny suit': '\u51cc\u4e71\u7684\u5154\u5973\u90ce\u88c5',
  'disheveled black bunny suit': '\u51cc\u4e71\u7684\u9ed1\u8272\u5154\u5973\u90ce\u88c5',
  'roswaal mansion maid uniform': '\u5973\u4ec6\u88c5',
  'white towel': '\u767d\u8272\u6d74\u5dfe',
  'bath towel': '\u6d74\u5dfe',
  'naked towel': '\u6d74\u5dfe',
  'wedding dress': '\u5a5a\u7eb1',
  'bridal veil': '\u65b0\u5a18\u5934\u7eb1',
});
const cacheDir = path.resolve(options.cacheDir ?? defaultCacheDir);
const outputDir = path.resolve(options.outputDir ?? defaultOutputDir);
const translationCache = loadJson(
  options.translationCache ?? defaultTranslationCache,
  {},
);
const classificationCache = loadJson(
  options.classificationCache ?? defaultClassificationCache,
  {},
);

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort()
  .filter((file) =>
    options.nameContains
      ? file.toLowerCase().includes(options.nameContains.toLowerCase())
      : true,
  )
  .slice(0, options.limit ?? undefined);

const report = {
  cache_dir: cacheDir,
  output_dir: outputDir,
  apply: options.apply,
  files_scanned: files.length,
  files_changed: 0,
  role_count: 0,
  stage_count: 0,
  role_display_fallback_count: 0,
  stage_label_fallback_count: 0,
  rows: [],
};

if (options.apply) {
  fs.mkdirSync(outputDir, { recursive: true });
}

for (const file of files) {
  const sourcePath = path.join(cacheDir, file);
  const cache = loadJson(sourcePath, null);
  if (!cache) continue;
  const result = buildExtraction(cache);
  const updated = {
    ...cache,
    updatedAt: new Date().toISOString(),
    aiRoleExtraction: result.extraction,
    aiRoleExtractionChunks: [],
    aiRoleExtractionDraftCollapsed: false,
    mapping: mappingWithRoleAssemblies(cache, result.extraction),
  };
  const changed = JSON.stringify(cache) !== JSON.stringify(updated);
  if (changed) {
    report.files_changed += 1;
  }
  report.role_count += result.extraction.roles.length;
  report.stage_count += result.extraction.roles.reduce(
    (count, role) => count + role.stages.length,
    0,
  );
  report.role_display_fallback_count += result.roleDisplayFallbackCount;
  report.stage_label_fallback_count += result.stageLabelFallbackCount;
  report.rows.push({
    file_name: file,
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    frame_count: frameList(cache).length,
    role_count: result.extraction.roles.length,
    stage_count: result.extraction.roles.reduce(
      (count, role) => count + role.stages.length,
      0,
    ),
    role_display_fallback_count: result.roleDisplayFallbackCount,
    stage_label_fallback_count: result.stageLabelFallbackCount,
    warnings: result.warnings,
  });
  if (options.apply) {
    fs.writeFileSync(
      path.join(outputDir, file),
      `${JSON.stringify(updated, null, 2)}\n`,
      'utf8',
    );
  }
}

console.log(JSON.stringify(report, null, 2));
if (options.report) {
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(options.report, `${JSON.stringify(report, null, 2)}\n`);
}

function buildExtraction(cache) {
  const frames = frameList(cache).filter((frame) => isParsedFrame(frame));
  const hasNonEmptyCharacterSlots = frames.some((frame) =>
    (Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : []
    ).some((caption) => stringValue(caption).trim().length > 0),
  );
  const groups = new Map();
  const roleDisplayFallbacks = new Set();
  let stageLabelFallbackCount = 0;
  const warnings = [];
  const collidingIdentityKeys = collectCollidingConcreteIdentityKeys(frames);
  const slotIdentityAnchors = collectSlotIdentityAnchors(frames);

  for (const frame of frames) {
    const frameIndex = Number(frame.index);
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    const baseTags = parseTags(frame.parsed?.baseCaption);
    let frameHadRoleCaption = false;
    captions.forEach((caption, slot) => {
      if (!stringValue(caption).trim()) return;
      const tags = parseTags(caption);
      if (tags.length === 0) return;
      const sourceId = `slot-${slot}`;
      const sourceIdentity = sanitizeIdentityForRole(identityForTags(tags), tags);
      if (shouldSkipCaptionAsRole(tags, sourceIdentity)) return;
      const anchor = slotIdentityAnchors.get(sourceId);
      const anchoredIdentity =
        sourceIdentity.concreteKey.length === 0 &&
        anchor &&
        canAttachGenericCaptionToAnchor(tags, sourceIdentity, anchor)
          ? mergeIdentities(anchor.identity, sourceIdentity)
          : sourceIdentity;
      const identity = sanitizeIdentityForRole(anchoredIdentity, tags);
      const characterKey = characterIdentityKey(identity);
      const groupKey =
        identity.concreteKey.length > 0
          ? `character:${characterKey}`
          : `generic:${genericRoleIdentityKey(identity, tags, sourceId)}`;
      const group = groups.get(groupKey) ?? {
        key: groupKey,
        sourceIds: new Map(),
        frames: new Set(),
        frameTags: [],
        identity,
      };
      if (
        group.identity.concrete.length === 0 &&
        identity.concrete.length > 0
      ) {
        group.identity = identity;
      } else {
        group.identity = sanitizeIdentityForRole(
          mergeIdentities(group.identity, identity),
        );
      }
      group.frames.add(frameIndex);
      frameHadRoleCaption = true;
      const sourceFrames = group.sourceIds.get(sourceId) ?? new Set();
      sourceFrames.add(frameIndex);
      group.sourceIds.set(sourceId, sourceFrames);
      group.frameTags.push({ frameIndex, sourceId, tags, baseTags, identity });
      groups.set(groupKey, group);
    });
    if (!frameHadRoleCaption && baseTags.length > 0) {
      const sourceId = 'base';
      const sourceIdentity = sanitizeIdentityForRole(identityForTags(baseTags), baseTags);
      if (!shouldSkipCaptionAsRole(baseTags, sourceIdentity)) {
        const identity = sanitizeIdentityForRole(sourceIdentity, baseTags);
        const characterKey = characterIdentityKey(identity);
        const groupKey =
          identity.concreteKey.length > 0
            ? `character:${characterKey}`
            : `generic:${genericRoleIdentityKey(identity, baseTags, sourceId)}`;
        const group = groups.get(groupKey) ?? {
          key: groupKey,
          sourceIds: new Map(),
          frames: new Set(),
          frameTags: [],
          identity,
        };
        if (
          group.identity.concrete.length === 0 &&
          identity.concrete.length > 0
        ) {
          group.identity = identity;
        } else {
          group.identity = sanitizeIdentityForRole(
            mergeIdentities(group.identity, identity),
          );
        }
        group.frames.add(frameIndex);
        const sourceFrames = group.sourceIds.get(sourceId) ?? new Set();
        sourceFrames.add(frameIndex);
        group.sourceIds.set(sourceId, sourceFrames);
        group.frameTags.push({ frameIndex, sourceId, tags: baseTags, baseTags, identity });
        groups.set(groupKey, group);
      }
    }
  }

  const roles = [];
  const usedRoleIds = new Set();
  const baseFrameGroupCount = countBaseFrameGroupMemberships(groups);
  for (const group of [...groups.values()].sort(compareGroups)) {
    const fields = fieldsForGroup(group);
    const display = displayNameForGroup(group, fields.identityTerms);
    if (display.fallback) roleDisplayFallbacks.add(group.key);
    const roleId = uniqueId(
      group.identity.concrete.length > 0
        ? `role-${safeId(group.identity.concrete[0])}`
        : `role-${safeId(group.key.replace(/^generic:/, ''))}`,
      usedRoleIds,
    );
    const frameIndexes = sortedInts(group.frames);
    const appearances = [...group.sourceIds.entries()]
      .sort((left, right) => left[0].localeCompare(right[0]))
      .map(([sourceId, sourceFrames]) => ({
        source_id: sourceId,
        source_kind: sourceId === 'base' ? 'base' : 'slot',
        frame_indexes: sortedInts(sourceFrames),
      }));
    const stageSourceGroups = stageGroupsForGroup(group);
    const stages = disambiguateDuplicateStageLabels(
      mergeStagesByLabel(
        stageSourceGroups.map((stageGroup, index) => {
        const stageFields = fieldsForGroup(stageGroup);
        const label = stageLabelForGroup(stageGroup, stageFields);
        if (label.fallback) stageLabelFallbackCount += 1;
        return {
          stage_id: `stage-${index + 1}`,
          label: label.label,
          appearance_group_id: `appearance-${index + 1}`,
          merge_with_stage_ids: [],
          field_reasons: fieldReasons(stageFields),
          confidence: stageFields.evidenceTerms.length > 0 ? 0.72 : 0.58,
          frame_indexes: sortedInts(stageGroup.frames),
          semantic_merge_key: stageGroup.semanticKey ?? stageGroup.key,
          identity: stageFields.identity,
          upper_body: stageFields.upperBody,
          lower_body: stageFields.lowerBody,
          upper_clothing: stageFields.upperClothing,
          lower_clothing: stageFields.lowerClothing,
          evidence_terms: stageFields.evidenceTerms,
          missing_fields: missingFields(stageFields),
          warnings: label.fallback ? ['stage_label_needs_manual_review'] : [],
        };
        }),
      ),
    );
    const rawIdentityTags = unique([
      ...(group.identity.concrete ?? []),
      ...(group.identity.rawGeneric ?? []),
    ]);
    const promptTerms = promptTermsForRoleGroup(roleId, group, {
      baseFrameGroupCount,
    });
    roles.push({
      source_role_id: roleId,
      source_kind:
        appearances.length > 1
          ? 'cross_slot'
          : appearances[0]?.source_kind === 'base'
            ? 'base'
            : 'slot',
      display_name: display.name,
      role_reason:
        'Offline Codex rebuild from scriptSnapshot frame tag evidence; no user API used.',
      canonical_name: group.identity.canonicalName,
      franchise: group.identity.franchise,
      raw_identity_tags: rawIdentityTags,
      variant_tags: group.identity.variantTags,
      merge_with_role_id: '',
      confidence: fields.evidenceTerms.length > 0 ? 0.72 : 0.58,
      frame_indexes: frameIndexes,
      appearances,
      evidence_terms: unique(stages.flatMap((stage) => stage.evidence_terms)),
      warnings: display.fallback ? ['display_name_needs_manual_review'] : [],
      stages,
      unassigned_terms: [],
      prompt_terms: promptTerms,
    });
  }

  if (!hasNonEmptyCharacterSlots && frames.length > 0) {
    warnings.push(
      'No non-empty character slots were found; base-only script requires manual role review.',
    );
  } else if (roles.length === 0 && frames.length > 0) {
    warnings.push('No safe role evidence was found after filtering.');
  }

  const status =
    roles.length > 0
      ? 'ready'
      : hasNonEmptyCharacterSlots
        ? 'needs_more_evidence'
        : 'needs_more_evidence';
  return {
    extraction: {
      schema_version: 1,
      status,
      confidence: roles.length > 0 ? 0.7 : 0,
      roles,
      artist_chains: artistChainsForFrames(frames),
      scene_terms: scenePromptTermsForFrames(frames),
      strong_filter_keywords: strongFilterKeywordsForFrames(frames),
      attention_items: warnings.map((message, index) => ({
        id: `offline-warning-${index + 1}`,
        kind: 'offline_rebuild_warning',
        message,
        blocking: false,
      })),
      unassigned_terms: [],
      evidence_requests: [],
    },
    roleDisplayFallbackCount: roleDisplayFallbacks.size,
    stageLabelFallbackCount,
    warnings,
  };
}

function collectCollidingConcreteIdentityKeys(frames) {
  const result = new Set();
  for (const frame of frames) {
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    const slotsByKey = new Map();
    captions.forEach((caption, slot) => {
      if (!stringValue(caption).trim()) return;
      const identity = identityForTags(parseTags(caption));
      if (identity.concreteKey.length === 0) return;
      const key = characterIdentityKey(identity);
      const slots = slotsByKey.get(key) ?? new Set();
      slots.add(slot);
      slotsByKey.set(key, slots);
    });
    for (const [key, slots] of slotsByKey) {
      if (slots.size > 1) result.add(key);
    }
  }
  return result;
}

function mappingWithRoleAssemblies(cache, extraction) {
  const mapping = cache.mapping ?? {
    id: `mapping-${cache.scriptId}`,
    scriptId: cache.scriptId,
    roleSwaps: [],
    artistSwap: null,
  };
  const previousAssemblies = Array.isArray(cache.mapping?.roleAssemblies)
    ? cache.mapping.roleAssemblies
    : [];
  return {
    ...mapping,
    roleAssemblies: extraction.roles.map((role) => {
      const previous = previousAssemblyForRole(previousAssemblies, role);
      return {
        sourceRoleId: role.source_role_id,
        displayLabel: role.display_name,
        sourceName: role.display_name,
        sourceAppearances: role.appearances.map((appearance) => ({
          sourceId: appearance.source_id,
          sourceKind: appearance.source_kind,
          frameIndexes: appearance.frame_indexes,
        })),
        stages: role.stages.map((stage) => {
          const previousStage = previousStageForStage(previous, stage);
          return {
            id: stage.stage_id,
            label: stage.label,
            frameIndexes: stage.frame_indexes,
            sourceSummary: stage.evidence_terms.join(', '),
            sourceParts: promptPartsToCamel(stage),
            ...retainedStageMapping(previousStage),
          };
        }),
      };
    }),
    rolePromptReplacements: rolePromptReplacementsForExtraction(extraction),
    scenePromptReplacements: scenePromptReplacementsForExtraction(extraction),
  };
}

function rolePromptReplacementsForExtraction(extraction) {
  return (extraction.roles ?? [])
    .map((role) => {
      const sourceRoleId = stringValue(role.source_role_id).trim();
      const terms = nonEmptyPromptTerms(role.prompt_terms);
      if (!sourceRoleId || terms.length === 0) return null;
      return {
        sourceRoleId,
        displayLabel: stringValue(role.display_name).trim() || sourceRoleId,
        sourcePreview: terms.map((term) => term.text).join(', '),
        rules: terms.map((term) => ({
          id: rolePromptReplacementRuleId(sourceRoleId, term),
          sourceTerms: [promptReplacementTermFromAi(term)],
        })),
      };
    })
    .filter(Boolean);
}

function scenePromptReplacementsForExtraction(extraction) {
  const terms = nonEmptyPromptTerms(extraction.scene_terms);
  if (terms.length === 0) return [];
  return [
    {
      id: 'scene-ai',
      label: 'Scene',
      rules: terms.map((term) => ({
        id: scenePromptReplacementRuleId(term),
        sourceTerms: [promptReplacementTermFromAi(term)],
      })),
    },
  ];
}

function nonEmptyPromptTerms(terms) {
  return (Array.isArray(terms) ? terms : []).filter((term) =>
    stringValue(term?.text).trim(),
  );
}

function promptReplacementTermFromAi(term) {
  return {
    id: stringValue(term.id).trim() || `term-${safeId(term.text)}`,
    text: stringValue(term.text).trim(),
    category: stringValue(term.category).trim() || 'identity',
    ...(stringValue(term.source_phrase).trim()
      ? { sourcePhrase: stringValue(term.source_phrase).trim() }
      : {}),
    ...(stringValue(term.source_location).trim()
      ? { sourceLocation: stringValue(term.source_location).trim() }
      : {}),
    ...(Array.isArray(term.frame_indexes) && term.frame_indexes.length > 0
      ? { frameIndexes: term.frame_indexes }
      : {}),
  };
}

function rolePromptReplacementRuleId(sourceRoleId, term) {
  const termId = stringValue(term.id).trim();
  return termId
    ? `role-${sourceRoleId}-${termId}`
    : `role-${sourceRoleId}-term-${safeId(term.text)}`;
}

function scenePromptReplacementRuleId(term) {
  const termId = stringValue(term.id).trim();
  return termId ? `scene-${termId}` : `scene-term-${safeId(term.text)}`;
}

function previousAssemblyForRole(previousAssemblies, role) {
  return (
    previousAssemblies.find(
      (assembly) => assembly.sourceRoleId === role.source_role_id,
    ) ??
    previousAssemblies.find(
      (assembly) =>
        normalizedTagKey(assembly.displayLabel) ===
          normalizedTagKey(role.display_name) ||
        normalizedTagKey(assembly.sourceName) === normalizedTagKey(role.display_name),
    ) ??
    null
  );
}

function previousStageForStage(previousAssembly, stage) {
  const stages = Array.isArray(previousAssembly?.stages)
    ? previousAssembly.stages
    : [];
  if (stages.length === 0) return null;
  let best = null;
  let bestScore = 0;
  const frameSet = new Set(stage.frame_indexes ?? []);
  for (const candidate of stages) {
    const candidateFrames = Array.isArray(candidate.frameIndexes)
      ? candidate.frameIndexes
      : [];
    let overlap = 0;
    for (const frameIndex of candidateFrames) {
      if (frameSet.has(frameIndex)) overlap += 1;
    }
    if (overlap > bestScore) {
      bestScore = overlap;
      best = candidate;
    }
  }
  if (bestScore > 0) return best;
  const byId = stages.find((candidate) => candidate.id === stage.stage_id);
  if (byId) return byId;
  return stages.length === 1 ? stages[0] : null;
}

function retainedStageMapping(stage) {
  if (!stage || typeof stage !== 'object') return {};
  const retained = {};
  for (const key of [
    'targetCharacterId',
    'targetUpperOutfitId',
    'targetLowerOutfitId',
    'omittedParts',
    'preservedParts',
    'manualParts',
  ]) {
    const value = stage[key];
    if (value == null) continue;
    if (typeof value === 'string' && value.length === 0) continue;
    if (Array.isArray(value) && value.length === 0) continue;
    if (
      typeof value === 'object' &&
      !Array.isArray(value) &&
      Object.keys(value).length === 0
    ) {
      continue;
    }
    retained[key] = value;
  }
  return retained;
}

function promptPartsToCamel(stage) {
  const parts = {};
  if (stage.identity.trim()) parts.identity = stage.identity;
  if (stage.upper_body.trim()) parts.upperBody = stage.upper_body;
  if (stage.lower_body.trim()) parts.lowerBody = stage.lower_body;
  if (stage.upper_clothing.trim()) parts.upperClothing = stage.upper_clothing;
  if (stage.lower_clothing.trim()) parts.lowerClothing = stage.lower_clothing;
  return parts;
}

function countBaseFrameGroupMemberships(groups) {
  const counts = new Map();
  for (const group of groups.values()) {
    const baseFrames = group.sourceIds?.get('base') ?? new Set();
    for (const frameIndex of baseFrames) {
      counts.set(frameIndex, (counts.get(frameIndex) ?? 0) + 1);
    }
  }
  return counts;
}

function promptTermsForRoleGroup(roleId, group, context = {}) {
  const terms = new Map();
  for (const entry of group.frameTags ?? []) {
    const frameIndex = Number(entry.frameIndex);
    if (!Number.isInteger(frameIndex)) continue;
    const normalizedEntryTags = (entry.tags ?? [])
      .map(normalizedTagKey)
      .filter(Boolean);
    for (const tag of entry.tags ?? []) {
      const normalized = normalizedTagKey(tag);
      if (!normalized) continue;
      const clothingPrompt = clothingPromptTermForTag(tag);
      if (clothingPrompt) {
        if (shouldSkipBaseClothingPromptTerm(entry, context)) {
          continue;
        }
        const clothingCategory = clothingPromptTermCategoryForTag(tag);
        addPromptTerm(terms, {
          category: clothingCategory,
          text: clothingPrompt,
          frameIndex,
          sourcePhrase: cleanTag(tag),
          sourceLocation: `${entry.sourceId || 'slot'} prompt`,
        });
        continue;
      }
      if (
        (isVisualDisplacementTermForStageKey(normalized) &&
          !hasTornReplacementEvidence(normalized)) ||
        isHeldOrUnwornClothingTag(normalized, normalizedEntryTags) ||
        isHeldTowelTag(normalized, normalizedEntryTags)
      ) {
        continue;
      }

      const routed = categoryForTag(tag);
      if (routed === 'identity') {
        if (!isIdentityTermAllowedForGroup(group, tag)) continue;
        const text = identityFieldTermForTag(tag);
        if (isGenericPromptIdentityTerm(text)) continue;
        if (shouldSkipPromptReplacementTerm(text, 'identity')) continue;
        addPromptTerm(terms, {
          category: 'identity',
          text,
          frameIndex,
          sourcePhrase: cleanTag(tag),
          sourceLocation: `${entry.sourceId || 'slot'} prompt`,
        });
      } else if (routed === 'upperBody' || routed === 'lowerBody') {
        addPromptTerm(terms, {
          category: 'body',
          text: roleFieldTermForCategory(tag, routed),
          frameIndex,
          sourcePhrase: cleanTag(tag),
          sourceLocation: `${entry.sourceId || 'slot'} prompt`,
        });
      } else if (routed === 'upperClothing' || routed === 'lowerClothing') {
        addPromptTerm(terms, {
          category: 'clothing',
          text: roleFieldTermForCategory(tag, routed),
          frameIndex,
          sourcePhrase: cleanTag(tag),
          sourceLocation: `${entry.sourceId || 'slot'} prompt`,
        });
      }
    }
  }
  const identityFrames = sortedInts(group.frames);
  for (const tag of uniqueExact([
    ...(group.identity?.concrete ?? []),
    ...(group.identity?.generic ?? []),
    ...(group.identity?.rawGeneric ?? []),
  ])) {
    const text = identityFieldTermForTag(tag);
    if (isGenericPromptIdentityTerm(text)) continue;
    if (shouldSkipPromptReplacementTerm(text, 'identity')) continue;
    for (const frameIndex of identityFrames) {
      addPromptTerm(terms, {
        category: 'identity',
        text,
        frameIndex,
        sourcePhrase: cleanTag(tag),
        sourceLocation: 'role identity evidence',
      });
    }
  }
  return promptTermRowsFromMap(terms, `role-${safeId(roleId)}`);
}

function shouldSkipBaseClothingPromptTerm(entry, context) {
  if (entry?.sourceId !== 'base') return false;
  const frameIndex = Number(entry.frameIndex);
  if (!Number.isInteger(frameIndex)) return true;
  const count = context?.baseFrameGroupCount?.get(frameIndex) ?? 0;
  return count !== 1;
}

function promptTermsWithIdentityAnchors(promptTerms, rawIdentityTags, frameIndexes, roleId) {
  const terms = new Map();
  for (const term of promptTerms) {
    const key = `${term.category}\u001f${normalizedTagKey(term.text)}`;
    terms.set(key, {
      category: term.category,
      text: term.text,
      sourcePhrase: term.source_phrase,
      sourceLocation: term.source_location,
      frames: new Set(term.frame_indexes ?? []),
    });
  }
  for (const tag of rawIdentityTags ?? []) {
    const text = identityFieldTermForTag(tag);
    if (isGenericPromptIdentityTerm(text)) continue;
    if (shouldSkipPromptReplacementTerm(text, 'identity')) continue;
    for (const frameIndex of frameIndexes ?? []) {
      addPromptTerm(terms, {
        category: 'identity',
        text,
        frameIndex,
        sourcePhrase: cleanTag(tag),
        sourceLocation: 'role identity evidence',
      });
    }
  }
  return promptTermRowsFromMap(terms, `role-${safeId(roleId)}`);
}

function scenePromptTermsForFrames(frames) {
  const terms = new Map();
  for (const frame of frames) {
    const frameIndex = Number(frame.index);
    if (!Number.isInteger(frameIndex)) continue;
    for (const tag of parseTags(frame.parsed?.baseCaption)) {
      if (!isScenePromptReplacementTerm(tag)) continue;
      addPromptTerm(terms, {
        category: 'scene',
        text: cleanTag(tag),
        frameIndex,
        sourcePhrase: cleanTag(tag),
        sourceLocation: 'base prompt',
      });
    }
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slot) => {
      for (const tag of parseTags(caption)) {
        if (!isScenePromptReplacementTerm(tag)) continue;
        addPromptTerm(terms, {
          category: 'scene',
          text: cleanTag(tag),
          frameIndex,
          sourcePhrase: cleanTag(tag),
          sourceLocation: `slot-${slot} prompt`,
        });
      }
    });
  }
  return promptTermRowsFromMap(terms, 'scene');
}

function isScenePromptReplacementTerm(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return false;
  if (containsGarmentOrClothingToken(normalized)) return false;
  if (isKnownFranchiseCharacterTag(tag, normalized) || isVariantNamedCharacterTag(tag)) {
    return false;
  }
  if (
    /\b(princess connect|blue archive|azur lane|genshin impact|honkai|star rail|arknights|granblue fantasy|zenless zone zero|re zero|date a live|hololive|idolmaster|touhou|pokemon|fate)\b/.test(
      normalized,
    )
  ) {
    return false;
  }
  if (
    /\b(hair|eyes?|iris|pupil|ears?|horns?|halo|fangs?|skin|face|hat|cap|ornament|headdress|headwear|jewelry|earrings?|necklace|choker|collar|ribbon|bow|twintails?|ponytail|pigtails?|braids?|bangs|hairclip|hairband|glasses|crown|bracelet|tattoo|mole|cleavage|collarbone|shoulders?|armpits?|chest|breasts?|bust|midriff|abs|thighs?|legs?|feet|toes?|hips?|waist|navel|stomach)\b/.test(
      normalized,
    )
  ) {
    return false;
  }
  return /\b(bathroom|bath|bathtub|shower|onsen|hot spring|workshop|factory|garage|mechanic|school|classroom|train|subway|station|street|city|bedroom|bed|indoors|outdoors)\b/.test(
    normalized,
  );
}

function addPromptTerm(terms, item) {
  const text = cleanTag(item.text);
  if (!text) return;
  const category = item.category || 'identity';
  if (shouldSkipPromptReplacementTerm(text, category)) return;
  const key = `${category}\u001f${normalizedTagKey(text)}`;
  const existing = terms.get(key) ?? {
    category,
    text,
    sourcePhrase: cleanTag(item.sourcePhrase),
    sourceLocation: stringValue(item.sourceLocation).trim(),
    frames: new Set(),
  };
  if (Number.isInteger(item.frameIndex)) {
    existing.frames.add(item.frameIndex);
  }
  if (!existing.sourcePhrase && cleanTag(item.sourcePhrase)) {
    existing.sourcePhrase = cleanTag(item.sourcePhrase);
  }
  if (!existing.sourceLocation && stringValue(item.sourceLocation).trim()) {
    existing.sourceLocation = stringValue(item.sourceLocation).trim();
  }
  terms.set(key, existing);
}

function promptTermRowsFromMap(terms, idPrefix) {
  const order = new Map([
    ['identity', 0],
    ['body', 1],
    ['clothing', 2],
    ['clothingState', 3],
    ['scene', 4],
  ]);
  return [...terms.values()]
    .sort(
      (left, right) =>
        (order.get(left.category) ?? 99) - (order.get(right.category) ?? 99) ||
        left.text.localeCompare(right.text),
    )
    .map((term) => ({
      id: `${idPrefix}-${term.category}-${safeId(term.text)}`,
      text: term.text,
      category: term.category,
      source_phrase: term.sourcePhrase || term.text,
      source_location: term.sourceLocation,
      frame_indexes: sortedInts(term.frames),
    }));
}

function clothingPromptTermForTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return '';
  if (isKnownFranchiseCharacterTag(tag, normalized) || isVariantNamedCharacterTag(tag)) {
    return '';
  }
  if (isOtherCharacterClothingActionTag(normalized)) return '';
  if (isNonClothingPhraseWithClothingToken(normalized)) return '';
  if (!isAllowedClothingStatePromptTerm(normalized) && !containsGarmentOrClothingToken(normalized)) {
    return '';
  }
  const text = cleanPromptReplacementStateTag(tag);
  return text || cleanTag(tag);
}

function clothingPromptTermCategoryForTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return 'clothing';
  return isAllowedClothingStatePromptTerm(normalized) ? 'clothingState' : 'clothing';
}

function clothingStatePromptTermForTag(tag) {
  const text = clothingPromptTermForTag(tag);
  if (!text) return '';
  return clothingPromptTermCategoryForTag(tag) === 'clothingState' ? text : '';
}

function cleanPromptReplacementStateTag(tag) {
  let text = cleanTag(tag);
  if (!text) return '';
  let previous = '';
  while (previous !== text) {
    previous = text;
    text = text.replace(/^[{}\[\]\s]+|[{}\[\]\s]+$/g, '').trim();
  }
  return text.replace(/\s+/g, ' ').trim();
}

function isAllowedClothingStatePromptTerm(normalized) {
  if (!normalized) return false;
  if (isCrossSubjectClothingCompositionTerm(normalized)) return false;
  if (/^(?:top down bottom up|top-down bottom-up)$/.test(normalized)) return false;
  if (/^(?:no panties|no underwear|no bra|no clothes)$/.test(normalized)) {
    return true;
  }
  if (/^(?:no shirt|no pants|no skirt|no socks|no shoes|no footwear)$/.test(normalized)) {
    return true;
  }
  if (
    /^(?:bottomless|bottomless female|topless|topless female|male topless|nude|naked|fully nude|fully naked|completely nude|completely naked|com pletely nude|compeltely nude)$/.test(
      normalized,
    )
  ) {
    return true;
  }
  if (/^(?:partially undressed|undressing|undressed|forced exposure)$/.test(normalized)) {
    return true;
  }
  if (/^(?:clothed|fully clothed|partially clothed)$/.test(normalized)) {
    return true;
  }
  return isClothingRelatedActionOrStateTerm(normalized);
}

function isClothingRelatedActionOrStateTerm(normalized) {
  if (!containsGarmentOrClothingToken(normalized)) return false;
  return (
    /\b(aside|pulled aside|pull aside|pull(?:ed|ing)?|lift(?:ed|ing)?|tug(?:ged|ging)?|open(?:ed|ing)?|unbutton(?:ed|ing)?|take off|taking off|remov(?:e|ed|ing)|tear(?:ing)?|torn|ripped|damaged|shredded|burn(?:ed|t)|burning|dirt|wet|soaked|stained|dirty|muddy|bloodstained|transparent|see through|see-through|yank(?:ed|ing)?(?: down)?|down|off|slip(?:ped|ping)?|flip(?:ped|ping)?|around one leg|on floor|on the floor|at floor|around waist|discarded|unworn|dropped|scattered|holding|in hand)\b/.test(
      normalized,
    ) ||
    /\b(?:through|under|over|inside)\s+clothes?\b/.test(normalized) ||
    /\b(?:fire|dirt|mud|blood)\s+on\s+clothes?\b/.test(normalized) ||
    /\b(breasts? out|one breast out|open clothes|open shirt|open jacket|open kimono|open towel|partially undressed)\b/.test(
      normalized,
    ) ||
    /(脱衣|脱ぎ|脱い|脱げ|脱が|破れ|破損|破损|裂け|撕裂|濡れ|湿|濕|汚れ|污|ずらし|ずらされ|めく|捲|開き|開け|はだけ|半脱ぎ|拉开|拉開|掀起|脱下|未穿|拿着)/.test(
      normalized,
    )
  );
}

function containsGarmentOrClothingToken(normalized) {
  if (normalized === 'top') return true;
  if (
    /\b(clothes?|clothing|outfits?|costumes?|attire|apparel|garb|shirt|blouse|halter top|crop top|tank top|bikini top|bra|bikini(?: bottom)?|swimsuits?|swimwear|one piece swimsuit|leotard|bodysuit|dress|skirt|kimono|yukata|uniform|serafuku|jacket|coat|hoodie|hood|bunny suit|bunny outfit|maid outfit|suit|pant(?:y|ies)|underwear|underclothes|lingerie|pants|shorts|stockings?|pantyhose|thighhighs?|socks?|shoes?|footwear|boots?|sneakers?|sandals?|heels?|legwear|towel|strap|sleeves?|garter|robe|apron|armor|vest|cloak|blazer|sweater)\b/.test(
      normalized,
    )
  ) {
    return true;
  }
  return /(服饰|服飾|服装|服裝|衣服|衣装|衣裝|衣裳|衣類|衣类|制服|校服|水着|泳装|泳裝|浴衣|和服|着物|メイド服|メイド衣装|下着|パンツ|ブラジャー|靴下|靴|ブーツ|スカート|シャツ|ブラウス|ワンピース|コスチューム|衣裳)/.test(
    normalized,
  );
}

function isCrossSubjectClothingCompositionTerm(normalized) {
  return /\bclothed (?:female|girl|woman|male|boy|man) nude (?:female|girl|woman|male|boy|man)\b/.test(
    normalized,
  );
}

function isNonClothingPhraseWithClothingToken(normalized) {
  if (/^(?:top down bottom up|top-down bottom-up)$/.test(normalized)) return true;
  if (/\b(?:girl|boy|woman|man|female|male)\s+on\s+top\b/.test(normalized)) {
    return true;
  }
  if (/\bdry(?:ing)?\s+with\s+(?:a\s+)?towel\b/.test(normalized)) return true;
  return false;
}

function shouldSkipPromptReplacementTerm(term, category) {
  const normalized = normalizedTagKey(term);
  if (!normalized) return true;
  if (category === 'scene') return false;
  if (category === 'clothingState') {
    return !isAllowedClothingStatePromptTerm(normalized);
  }
  if (category === 'clothing') {
    if (isCrossSubjectClothingCompositionTerm(normalized)) return true;
    if (isOtherCharacterClothingActionTag(normalized)) return true;
    if (isNonClothingPhraseWithClothingToken(normalized)) return true;
    return !containsGarmentOrClothingToken(normalized);
  }
  if (isHardNonRoleTerm(normalized)) return true;
  if (
    /\b(averting eyes?|looking|watching|staring|closed eyes?|open mouth|blush|crying|smile|pain|panic|dazed|motion blur|sound effects?)\b/.test(
      normalized,
    )
  ) {
    return true;
  }
  if (
    /\b(spread|sperad|spraed|apart|standing|sitting|lying|kneeling|punch|kick|grab|hold|holding|lift|lifting|pull|pushed|bouncing|hanging breasts?|heaving|squeezed|outstretched)\b/.test(
      normalized,
    )
  ) {
    return true;
  }
  return false;
}

function isGenericPromptIdentityTerm(term) {
  const normalized = normalizedTagKey(term);
  if (!normalized) return true;
  if (isBasicGenericIdentity(normalized)) return true;
  return /^(?:solo|1girl|2girls|girls?|1boy|2boys|boys?|female|male|woman|man|women|men)$/.test(
    normalized,
  );
}

function identityForTags(tags) {
  const concrete = [];
  const generic = [];
  const rawGeneric = [];
  for (const tag of tags) {
    const normalized = normalizedTagKey(tag);
    const genericIdentity = genericIdentityForNormalized(normalized);
    if (isHardNonRoleTerm(normalized)) {
      if (genericIdentity) {
        generic.push(genericIdentity.tag);
        rawGeneric.push(tag);
      }
      continue;
    }
    if (isConcreteCharacterTag(tag)) {
      concrete.push(tag);
      continue;
    }
    if (genericIdentity) {
      generic.push(genericIdentity.tag);
      rawGeneric.push(tag);
    }
  }
  if (concrete.length === 0 && generic.length === 0) {
    const inferred = inferredGenericIdentityFromEvidence(tags);
    if (inferred) generic.push(inferred.tag);
  }
  const uniqueConcrete = unique(concrete);
  const parsed = parseCharacterTag(uniqueConcrete[0] ?? '');
  return {
    concrete: uniqueConcrete,
    concreteKey: uniqueConcrete[0] ? normalizedTagKey(uniqueConcrete[0]) : '',
    generic: unique(generic),
    rawGeneric: unique(rawGeneric),
    genericKey: generic[0] ? normalizedTagKey(generic[0]) : '',
    canonicalName: parsed.canonicalName,
    franchise: parsed.franchise,
    variantTags: parsed.variantTags,
  };
}

function inferredGenericIdentityFromEvidence(tags) {
  const normalized = tags.map(normalizedTagKey).filter(Boolean).join(', ');
  if (
    /\b(breasts?|bra|panties|skirt|dress|bikini|leotard|camisole|thighhighs?|animal ears|long hair|twintails?)\b/.test(
      normalized,
    )
  ) {
    return genericIdentityMap.girl;
  }
  if (
    /\b(?:pov hands?|pov|muscular|tan skin|brown skin)\b/.test(normalized) &&
    /\b(?:nude|naked|muscular)\b/.test(normalized)
  ) {
    return genericIdentityMap.male;
  }
  if (/\b(huge penis|pov penis|male black|male white|male shirt|male swimsuit)\b/.test(normalized)) {
    return genericIdentityMap.male;
  }
  return null;
}

function characterIdentityKey(identity) {
  const concrete = identity.concrete[0] ?? '';
  const parsed = parseCharacterTag(concrete);
  const canonical = normalizedTagKey(parsed.canonicalName || concrete);
  const franchise = normalizedTagKey(parsed.franchise);
  return franchise ? `${canonical}:${franchise}` : canonical || identity.concreteKey;
}

function emptyIdentity() {
  return {
    concrete: [],
    concreteKey: '',
    generic: [],
    rawGeneric: [],
    genericKey: '',
    canonicalName: '',
    franchise: '',
    variantTags: [],
  };
}

function mergeIdentities(left, right) {
  const concrete = unique([...(left?.concrete ?? []), ...(right?.concrete ?? [])]);
  const generic = unique([...(left?.generic ?? []), ...(right?.generic ?? [])]);
  const rawGeneric = unique([
    ...(left?.rawGeneric ?? []),
    ...(right?.rawGeneric ?? []),
  ]);
  const parsed = parseCharacterTag(concrete[0] ?? '');
  return {
    concrete,
    concreteKey: concrete[0] ? normalizedTagKey(concrete[0]) : '',
    generic,
    rawGeneric,
    genericKey: generic[0] ? normalizedTagKey(generic[0]) : '',
    canonicalName:
      parsed.canonicalName || left?.canonicalName || right?.canonicalName || '',
    franchise: parsed.franchise || left?.franchise || right?.franchise || '',
    variantTags: unique([
      ...(left?.variantTags ?? []),
      ...(right?.variantTags ?? []),
      ...parsed.variantTags,
    ]),
  };
}

function sanitizeIdentityForRole(identity) {
  const concrete = unique(identity?.concrete ?? []);
  const primaryConcrete = concrete[0] ? [concrete[0]] : [];
  const parsed = parseCharacterTag(primaryConcrete[0] ?? '');
  const base = {
    concrete: primaryConcrete,
    concreteKey: primaryConcrete[0] ? normalizedTagKey(primaryConcrete[0]) : '',
    generic: unique(identity?.generic ?? []),
    rawGeneric: unique(identity?.rawGeneric ?? []),
    genericKey: '',
    canonicalName: parsed.canonicalName || identity?.canonicalName || '',
    franchise: parsed.franchise || identity?.franchise || '',
    variantTags: unique([...(identity?.variantTags ?? []), ...parsed.variantTags]),
  };
  const preferredGender = preferredIdentityGender(base);
  const filteredGeneric =
    preferredGender === 'female' || preferredGender === 'male'
      ? base.generic.filter((term) => {
          const gender = genderForIdentityTerm(term);
          return !gender || gender === preferredGender;
        })
      : filterMixedGenericIdentity(base.generic);
  base.generic = unique(filteredGeneric);
  base.genericKey = base.generic[0] ? normalizedTagKey(base.generic[0]) : '';
  return base;
}

function filterMixedGenericIdentity(genericTerms) {
  const terms = unique(genericTerms ?? []);
  const hasFemale = terms.some((term) => genderForIdentityTerm(term) === 'female');
  const hasMale = terms.some((term) => genderForIdentityTerm(term) === 'male');
  if (!hasFemale || !hasMale) return terms;
  const hasSpecificMale = terms.some(
    (term) =>
      genderForIdentityTerm(term) === 'male' && !isBasicGenericIdentity(term),
  );
  if (hasSpecificMale) {
    return terms.filter((term) => genderForIdentityTerm(term) !== 'female');
  }
  return terms.filter((term) => genderForIdentityTerm(term) !== 'male');
}

function preferredIdentityGender(identity) {
  const concreteText = normalizedTagKey(
    [
      ...(identity?.concrete ?? []),
      identity?.canonicalName ?? '',
      identity?.franchise ?? '',
    ].join(' '),
  );
  if (
    /\b(commander|sensei|doodle sensei|doctor|male focus|yuuki|asaba harumasa|aventurine|emiya shirou|natsuki subaru|aether|wise|bihyung|itsuka shido|shota|faceless male|fat man|old man|bald man|big man|muscular male|musclar male|dark[- ]?skinned male|dark[- ]?skined male|black[- ]?skinned male|black[- ]?skinnd male|naked man|ugly man|bald naked man|male|man)\b/.test(
      concreteText,
    )
  ) {
    return 'male';
  }
  const generics = identity?.generic ?? [];
  const hasFemale = generics.some((term) => genderForIdentityTerm(term) === 'female');
  const hasMale = generics.some((term) => genderForIdentityTerm(term) === 'male');
  if ((identity?.concrete ?? []).length > 0 && hasFemale && hasMale) {
    return 'female';
  }
  if (hasMale && !hasFemale) return 'male';
  if (hasFemale && !hasMale) return 'female';
  return '';
}

function genderForIdentityTerm(term) {
  const normalized = normalizedTagKey(term);
  if (/\b(1girl|2girls|girl|female|woman|loli)\b/.test(normalized)) return 'female';
  if (
    /\b(1boy|boy|male|man|men|guy|guys|shota|faceless male|fat man|dark skinned male|dark-skinned male|black man|black skinned male|muscular male|musclar male|bald man|old man|mature man|rugged man|big man|bandit|homeless man|homless man)\b/.test(
      normalized,
    )
  ) {
    return 'male';
  }
  return '';
}

function genericIdentityForNormalized(normalized) {
  if (genericIdentityMap[normalized]) return genericIdentityMap[normalized];
  if (/\bgiant\s+orc\b/.test(normalized)) {
    return genericIdentityMap['giant orc'];
  }
  if (/\borcs?\b/.test(normalized)) {
    return genericIdentityMap.orc;
  }
  if (/\bbandits?\b/.test(normalized)) {
    return genericIdentityMap.bandit;
  }
  if (/\b(?:homeless|homless)\s+man\b/.test(normalized)) {
    return genericIdentityMap['homeless man'];
  }
  if (/\brugged\s+man\b/.test(normalized)) {
    return genericIdentityMap['rugged man'];
  }
  if (/\bmature\s+(?:man|male)\b/.test(normalized)) {
    return genericIdentityMap['mature man'];
  }
  if (
    /\bdirty\s+fat\s+ugly\s+(?:homeless|homless)\s+man\b/.test(normalized) ||
    /\bbald\s+ugly\s+tall\s+fat\s+male\b/.test(normalized) ||
    /\bbald\s+ugly\b.*\bfat\s+male\b/.test(normalized) ||
    /\bugly\s+(?:fat\s+)?man\b/.test(normalized) ||
    /\bfat\s+(?:man|men|male)\b/.test(normalized)
  ) {
    return genericIdentityMap['fat man'];
  }
  if (/\bmale\s+bald\s+head\b|\bbald\s+head\b.*\bmale\b/.test(normalized)) {
    return genericIdentityMap['bald man'];
  }
  if (/\bmonster\s+boy\b/.test(normalized)) {
    return genericIdentityMap.monster;
  }
  if (/\btentacle\b.*\bmonster\b|\bmonster\b.*\btentacle\b/.test(normalized)) {
    return genericIdentityMap['tentacle monster'];
  }
  if (/\b(?:flower\s+)?(?:tentacle\s+)?vine\s+monster\b/.test(normalized)) {
    return genericIdentityMap.monster;
  }
  if (/\bfaceless\b.*\bmale\b|\bmale\b.*\bfaceless\b/.test(normalized)) {
    return genericIdentityMap['faceless male'];
  }
  if (/\b(?:dark|tan)\s+skin\b.*\bmale\b|\bmale\b.*\b(?:dark|tan)\s+skin\b/.test(normalized)) {
    return genericIdentityMap['dark-skinned male'];
  }
  if (/^(?:1\s*)?(?:girl|girls|female|woman)$|^2\s*girls?$/.test(normalized)) {
    return genericIdentityMap.girl;
  }
  if (
    /^(?:1\s*)?(?:boy|boys)$|^2\s*boys$/.test(normalized)
  ) {
    return genericIdentityMap.boy;
  }
  if (/^(?:1\s*)?(?:male|males|man|men|guy|guys)$|^2\s*(?:males|men|guys)$/.test(normalized)) {
    return genericIdentityMap.male;
  }
  return null;
}

function collectSlotIdentityAnchors(frames) {
  const bySlot = new Map();
  const roleCaptionCounts = new Map();
  for (const frame of frames) {
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slot) => {
      const tags = parseTags(caption);
      const identity = sanitizeIdentityForRole(identityForTags(tags), tags);
      if (tags.length === 0 || shouldSkipCaptionAsRole(tags, identity)) return;
      if (identity.concreteKey.length === 0) return;
      const sourceId = `slot-${slot}`;
      roleCaptionCounts.set(sourceId, (roleCaptionCounts.get(sourceId) ?? 0) + 1);
      const key = characterIdentityKey(identity);
      const slotMap = bySlot.get(sourceId) ?? new Map();
      const current =
        slotMap.get(key) ??
        {
          key,
          count: 0,
          identity: emptyIdentity(),
        };
      current.count += 1;
      current.identity = mergeIdentities(current.identity, identity);
      slotMap.set(key, current);
      bySlot.set(sourceId, slotMap);
    });
  }
  const anchors = new Map();
  for (const [sourceId, slotMap] of bySlot.entries()) {
    const entries = [...slotMap.values()].sort((left, right) => right.count - left.count);
    const total =
      roleCaptionCounts.get(sourceId) ??
      entries.reduce((sum, entry) => sum + entry.count, 0);
    const dominantGender = identityGender(entries[0]?.identity);
    const minCount = dominantGender === 'female' ? 2 : 3;
    const minRatio = dominantGender === 'female' ? 0.6 : 0.85;
    if (
      entries.length === 1 &&
      entries[0]?.count >= minCount &&
      entries[0].count / Math.max(1, total) >= minRatio
    ) {
      anchors.set(sourceId, entries[0]);
      continue;
    }
    if (entries[0]?.count >= minCount && entries[0].count / Math.max(1, total) >= minRatio) {
      anchors.set(sourceId, entries[0]);
    }
  }
  return anchors;
}

function shouldSkipCaptionAsRole(tags, identity) {
  const normalized = tags.map(normalizedTagKey).filter(Boolean);
  const hasExplicitBasic = hasExplicitBasicIdentity(tags);
  const hasStableEvidence = hasStableRoleEvidence(tags);
  const hasSpecificGeneric = hasSpecificGenericIdentity(identity);
  if (
    identity.concreteKey.length === 0 &&
    !hasExplicitBasic &&
    !hasSpecificGeneric &&
    !hasWholeCharacterPresenceEvidence(tags) &&
    normalized.some((tag) => /\b(pov hands?|only hands?|disembodied hands?)\b/.test(tag))
  ) {
    return true;
  }
  if (identity.concreteKey.length > 0) return false;
  if (normalized.length === 0) return true;
  if (normalized.every((tag) => isStageContextTerm(tag) || isHardNonRoleTerm(tag))) {
    return true;
  }
  if (identity.generic.length === 0 && !hasStableEvidence) return true;
  if (
    hasOnlyPartialHumanEvidence(tags) &&
    !hasSpecificGeneric &&
    !hasWholeCharacterPresenceEvidence(tags) &&
    !hasDurablePartialRoleEvidence(tags)
  ) {
    return true;
  }
  if (hasExplicitBasic && (hasStableEvidence || hasWholeCharacterPresenceEvidence(tags))) {
    return false;
  }
  if (!hasSpecificGeneric && !hasStableEvidence) {
    return true;
  }
  return false;
}

function canAttachGenericCaptionToAnchor(tags, identity, anchor) {
  if (!anchor?.identity) return false;
  if (hasNonHumanGenericIdentity(identity)) return false;
  if (
    anchor.identity.concreteKey &&
    identityGender(identity) === 'male' &&
    hasSpecificGenericIdentity(identity)
  ) {
    return false;
  }
  if (!hasStableRoleEvidence(tags) && !hasSpecificGenericIdentity(identity)) {
    return false;
  }
  const sourceGender = identityGender(identity);
  const anchorGender = identityGender(anchor.identity);
  if (sourceGender && anchorGender && sourceGender !== anchorGender) return false;
  return true;
}

function genericRoleIdentityKey(identity, tags, sourceId) {
  const normalized = tags.map(normalizedTagKey).filter(Boolean);
  const terms = [];
  for (const term of identity.generic) {
    const key = normalizedTagKey(term);
    if (!isBasicGenericIdentity(key)) terms.push(key);
  }
  for (const tag of normalized) {
    if (
      /\b(african|black man|black skinned male|dark skinned male|dark-skinned male|faceless male|fat man|big man|bald man|bald head|muscular male|musclar male|old man|homeless man|homless man|shota|bandit|orc|giant orc|goblin|monster|tentacle monster|octopus tentacle monster|flower tentacle vine monster|tentacle vine monster|vine monster)\b/.test(
        tag,
      )
    ) {
      terms.push(genericIdentityForNormalized(tag)?.tag ?? tag);
    }
  }
  if (terms.some((term) => /\b(goblin|orc|monster|tentacle monster|octopus tentacle monster)\b/.test(term))) {
    return uniqueExact(terms.map(normalizedTagKey))
      .filter((term) => /\b(goblin|orc|monster|tentacle)\b/.test(term))
      .sort()
      .join('-');
  }
  const specific = uniqueExact(terms.map(normalizedTagKey)).sort();
  if (specific.some((term) => /\bshota\b/.test(term))) return 'shota';
  if (specific.some((term) => /\b(muscular male|musclar male)\b/.test(term))) {
    return 'muscular-male';
  }
  if (
    specific.some((term) =>
      /\b(fat man|big man|old man|bald man|bald head|dark[- ]?skinned male|black skinned male|black man|faceless male|african)\b/.test(
        term,
      ),
    )
  ) {
    return 'anonymous-male';
  }
  if (specific.length > 0) return specific.join('-');
  if (identityGender(identity) === 'male') return 'anonymous-male';
  return `${identity.genericKey || 'role'}-${sourceId}`;
}

function hasStableRoleEvidence(tags) {
  for (const tag of tags) {
    const normalized = normalizedTagKey(tag);
    if (!normalized || isHardNonRoleTerm(normalized)) continue;
    if (hasWholeCharacterPresenceEvidence([tag])) return true;
    if (isHeldOrUnwornClothingTag(normalized, tags.map(normalizedTagKey))) continue;
    const category = categoryForTag(tag);
    if (
      category === 'upperBody' ||
      category === 'lowerBody' ||
      category === 'upperClothing' ||
      category === 'lowerClothing'
    ) {
      return true;
    }
  }
  return false;
}

function hasSpecificGenericIdentity(identity) {
  return (identity.generic ?? []).some((term) => !isBasicGenericIdentity(term));
}

function hasNonHumanGenericIdentity(identity) {
  return (identity.generic ?? []).some((term) =>
    /\b(goblin|monster|tentacle|orc)\b/.test(normalizedTagKey(term)),
  );
}

function isBasicGenericIdentity(term) {
  return /^(1girl|2girls|girl|girls|woman|female|1boy|boy|boys|man|men|male|guy|guys|child|student|loli)$/.test(
    normalizedTagKey(term),
  );
}

function identityGender(identity) {
  return preferredIdentityGender(sanitizeIdentityForRole(identity));
}

function hasOnlyPartialHumanEvidence(tags) {
  const normalizedTags = tags.map(normalizedTagKey).filter(Boolean);
  const partial = normalizedTags.some((tag) =>
    /\b(pov|disembodied hands?|pov hands?|pov arms?|only hands?|only lower body|only upper body|large hands?|transparent body|huge penis|penis|hand on pussy|fingering|licking nipple|suck .*nipple|pant bulge)\b/.test(
      tag,
    ),
  );
  if (!partial) return false;
  return !hasWholeCharacterPresenceEvidence(tags);
}

function hasDurablePartialRoleEvidence(tags) {
  for (const tag of tags) {
    const normalized = normalizedTagKey(tag);
    if (!normalized || isHardNonRoleTerm(normalized)) continue;
    if (
      /\b(student|hair|eyes?|shirt|pants|trousers|jacket|dress|skirt|robe|hat|ribbon|tail|ears?|uniform|suit)\b/.test(
        normalized,
      )
    ) {
      return true;
    }
    const category = categoryForTag(tag);
    if (
      category === 'upperBody' ||
      category === 'lowerBody' ||
      category === 'upperClothing' ||
      category === 'lowerClothing'
    ) {
      return true;
    }
  }
  return false;
}

function hasWholeCharacterPresenceEvidence(tags) {
  const normalized = tags.map(normalizedTagKey).filter(Boolean).join(', ');
  if (
    /\b(full body|whole body|entire body|body visible|torso|upper body|lower body|back view|from behind|standing|sitting|lying|kneeling|on back|on stomach|clothed|nude|naked|completely nude|naked man|naked male|nude male|shirtless|faceless|bald)\b/.test(
      normalized,
    )
  ) {
    return true;
  }
  return false;
}

function hasExplicitBasicIdentity(tags) {
  return tags
    .map(normalizedTagKey)
    .some((tag) =>
      /^(?:1\s*)?(?:girl|girls|female|woman|loli|boy|boys|male|males|man|men|guy|guys)$|^2\s*(?:girls|boys|males|men|guys)$/.test(
        tag,
      ),
    );
}

function frameLevelEntriesForGroup(group) {
  const byFrame = new Map();
  for (const entry of group.frameTags) {
    const current =
      byFrame.get(entry.frameIndex) ??
      {
        frameIndex: entry.frameIndex,
        sourceId: entry.sourceId,
        sourceIds: new Set(),
        tags: [],
        baseTags: [],
        identity: emptyIdentity(),
      };
    current.sourceIds.add(entry.sourceId);
    current.tags.push(...(entry.tags ?? []));
    current.baseTags.push(...(entry.baseTags ?? []));
    current.identity = sanitizeIdentityForRole(
      mergeIdentities(current.identity, entry.identity),
    );
    byFrame.set(entry.frameIndex, current);
  }
  return [...byFrame.values()]
    .map((entry) => ({
      frameIndex: entry.frameIndex,
      sourceId: [...entry.sourceIds].sort()[0] ?? entry.sourceId,
      sourceIds: [...entry.sourceIds].sort(),
      tags: unique(entry.tags),
      baseTags: unique(entry.baseTags),
      identity: entry.identity,
    }))
    .sort((left, right) => left.frameIndex - right.frameIndex);
}

function stageGroupsForGroup(group) {
  const entries = frameLevelEntriesForGroup(group).sort(
    (left, right) => left.frameIndex - right.frameIndex,
  );
  const stagesByKey = new Map();
  const recentConcreteStateKeys = new Map();
  for (const entry of entries) {
    const signature = stageSignatureForEntry(entry);
    let replacementKey = frameReplacementKeyForStageTags(entry.tags);
    replacementKey = smoothSparseStateReplacementKey(
      replacementKey,
      entry.frameIndex,
      recentConcreteStateKeys,
    );
    const stageKey =
      replacementKey === 'unspecified'
        ? signature.mergeKey
        : `replacement:${replacementKey}`;
    const current =
      stagesByKey.get(stageKey) ??
      {
        key: `${group.key}:${stageKey}`,
        sourceIds: new Map(),
        frames: new Set(),
        frameTags: [],
        identity: emptyIdentity(),
        semanticKey: stageKey,
        signatureTerms: new Set(signature.terms),
        signatureBucket: signature.bucket,
        lastFrameIndex: -1,
      };
    current.frames.add(entry.frameIndex);
    current.frameTags.push(entry);
    current.identity = sanitizeIdentityForRole(
      mergeIdentities(current.identity, entry.identity),
    );
    current.lastFrameIndex = entry.frameIndex;
    for (const term of signature.terms) current.signatureTerms.add(term);
    for (const sourceId of entry.sourceIds ?? [entry.sourceId]) {
      const sourceFrames = current.sourceIds.get(sourceId) ?? new Set();
      sourceFrames.add(entry.frameIndex);
      current.sourceIds.set(sourceId, sourceFrames);
    }
    stagesByKey.set(stageKey, current);
  }
  const stages = [...stagesByKey.values()].sort(
    (left, right) =>
      Math.min(...left.frames) - Math.min(...right.frames) ||
      left.key.localeCompare(right.key),
  );
  return stages.length > 0 ? stages : [group];
}

function smoothSparseStateReplacementKey(key, frameIndex, recentStateKeys) {
  const sparse = key.match(/^state:(topless|bottomless)(?::no-(?:upper|lower)-clothing)?$/);
  const concrete = key.match(/^state:(topless|bottomless):(.+)$/);
  if (sparse) {
    const recent = recentStateKeys.get(sparse[1]);
    if (recent && frameIndex - recent.frameIndex <= 12) return recent.key;
    return key;
  }
  if (concrete && !/^no-(?:upper|lower)-clothing$/.test(concrete[2])) {
    recentStateKeys.set(concrete[1], { key, frameIndex });
  }
  return key;
}

function frameReplacementKeyForStageTags(tags) {
  const normalized = tags.map(normalizedTagKey).filter(Boolean);
  const actualTowel = hasActualTowelForStageTags(normalized);
  const upper = [];
  const lower = [];
  for (const tag of normalized) {
    const term = replacementClothingTermForStageKey(tag, normalized);
    if (!term) continue;
    if (isLowerReplacementTermForStageKey(term)) lower.push(term);
    else upper.push(term);
  }
  const canonicalUpper = canonicalReplacementTermsForStageKey(upper);
  const canonicalLower = canonicalReplacementTermsForStageKey(lower);
  const state = new Set();
  for (const tag of normalized) {
    if (isHoldingTowelForStageKey(tag)) continue;
    if (/\b(breasts? out)\b/.test(tag)) continue;
    if (isNonRoleReplacementStateTermForStageKey(tag)) continue;
    if (/\b(topless|topless female)\b/.test(tag)) state.add('topless');
    if (/\b(bottomless)\b/.test(tag)) state.add('bottomless');
    if (/\b(nude|naked|completely nude|no clothes)\b/.test(tag)) {
      state.add('nude');
    }
  }
  const upperKey = canonicalUpper.sort().join('|');
  const lowerKey = canonicalLower.sort().join('|');
  if (actualTowel) return 'state:towel';
  if (state.has('topless')) {
    return `state:topless:${lowerKey || 'no-lower-clothing'}`;
  }
  if (state.has('bottomless')) {
    const clothing = [upperKey, lowerKey].filter(Boolean).join('|');
    return `state:bottomless:${clothing || 'no-upper-clothing'}`;
  }
  if (state.has('nude')) {
    const nudeLowerKey = uniqueExact(
      canonicalLower.filter(
        (term) =>
          baseReplacementTermForStageKey(term) !== 'no-underwear' &&
          baseReplacementTermForStageKey(term) !== 'footwear',
      ),
    )
      .sort()
      .join('|');
    const clothing = [upperKey, nudeLowerKey].filter(Boolean).join('|');
    return clothing ? `state:nude-with:${clothing}` : 'state:nude';
  }
  const core = coreClothingKeyForStageKey({
    upper: canonicalUpper,
    lower: canonicalLower,
  });
  return core || 'unspecified';
}

function canonicalReplacementTermsForStageKey(terms) {
  const uniqueTerms = uniqueExact(terms);
  const bases = new Set(uniqueTerms.map(baseReplacementTermForStageKey));
  const contradictionFiltered = uniqueTerms.filter((term) => {
    const base = baseReplacementTermForStageKey(term);
    if (bases.has('no-underwear') && ['underwear', 'underwear-only'].includes(base)) {
      return false;
    }
    if (bases.has('no-bra') && ['bra', 'lace-bra'].includes(base)) return false;
    if (bases.has('no-overalls') && base === 'overalls') return false;
    return true;
  });
  const specificityFiltered = contradictionFiltered.filter((term) => {
    const base = baseReplacementTermForStageKey(term);
    const modifiers = replacementModifierSetForStageKey(term);
    if (modifiers.size === 0) return true;
    return !contradictionFiltered.some((other) => {
      if (other === term || baseReplacementTermForStageKey(other) !== base) {
        return false;
      }
      const otherModifiers = replacementModifierSetForStageKey(other);
      return (
        otherModifiers.size > modifiers.size &&
        [...modifiers].every((modifier) => otherModifiers.has(modifier))
      );
    });
  });
  const basesWithSpecificTerms = new Set(
    specificityFiltered
      .filter((term) => stringValue(term).includes(':'))
      .map(baseReplacementTermForStageKey),
  );
  return specificityFiltered.filter((term) => {
    const base = baseReplacementTermForStageKey(term);
    return stringValue(term).includes(':') || !basesWithSpecificTerms.has(base);
  });
}

function replacementClothingTermForStageKey(tag, allTags = []) {
  if (isOtherCharacterClothingActionTag(tag)) return '';
  if (isHeldOrUnwornClothingTag(tag, allTags)) return '';
  if (isHeldTowelTag(tag, allTags)) return '';
  if (isVisualReplacementEvidenceTermForStageKey(tag)) {
    const visual = visualReplacementTermForStageKey(tag, allTags);
    if (visual) return visual;
  }
  if (isHardNonRoleTerm(tag)) return '';
  if (isActualTowelForStageKey(tag)) return 'towel';
  if (/\b(no bra)\b/.test(tag)) return 'no-bra';
  if (/\b(no panties|no underwear)\b/.test(tag)) return 'no-underwear';
  if (/\b(no overall|no overalls)\b/.test(tag)) return 'no-overalls';
  if (/\b(shoes? off|shoe removed|shoes removed)\b/.test(tag)) return 'no-footwear';
  return visualReplacementTermForStageKey(tag, allTags);
}

function visualReplacementTermForStageKey(tag, allTags = []) {
  const modifiers = visualReplacementModifiersForStageKey(tag, allTags);
  const term = (base) =>
    modifiers.length > 0 ? `${base}:${modifiers.join('+')}` : base;
  if (/\b(babydoll|baby doll|negligee|chemise|teddy)\b/.test(tag)) {
    return term('babydoll');
  }
  if (/\b(lingerie set|underwear set)\b/.test(tag)) return term('underwear-set');
  if (/\b(lingerie|sleepwear|nightgown)\b/.test(tag)) return term('lingerie-set');
  if (/\b(bra).*(panties|underwear)\b|\b(panties|underwear).*(bra)\b/.test(tag)) {
    return term('underwear-set');
  }
  if (/\b(mechanical panties|mechanical underwear)\b/.test(tag)) {
    return term('mechanical-underwear');
  }
  if (/\b(bunny suit|bunny girl outfit|bunny outfit)\b/.test(tag)) {
    return term('bunny-suit');
  }
  if (/\b(fundoshi|loincloth)\b/.test(tag)) return term('fundoshi');
  if (/\bmale\b.*\bswimsuit\b/.test(tag)) return term('swimsuit-bottom');
  if (/\b(bikini bottom only)\b/.test(tag)) return term('bikini-bottom-only');
  if (/\b(side tie bikini bottom|side-tie bikini bottom)\b/.test(tag)) {
    return term('side-tie-bikini-bottom');
  }
  if (/\b(bikini bottoms?)\b/.test(tag)) return term('bikini-bottom');
  if (/\b(micro bikini)\b/.test(tag)) return term('micro-bikini');
  if (/\b(maid bikini)\b/.test(tag)) return term('maid-bikini');
  if (/\b(bikini)\b/.test(tag)) return term('bikini');
  if (/\b(one[- ]piece swimsuit)\b/.test(tag)) return term('one-piece-swimsuit');
  if (/\b(school swimsuit|old school swimsuit)\b/.test(tag)) {
    return term('school-swimsuit');
  }
  if (/\b(swimsuit|swimwear)\b/.test(tag)) return term('swimsuit');
  if (/\b(bodysuit)\b/.test(tag)) return term('bodysuit');
  if (/\b(leotard)\b/.test(tag)) return term('leotard');
  if (/\b(underwear only)\b/.test(tag)) return term('underwear-only');
  if (/\b(panty|panties|underwear|briefs)\b/.test(tag)) return term('underwear');
  if (/\b(lace bra)\b/.test(tag)) return term('lace-bra');
  if (/\b(bra)\b/.test(tag)) return term('bra');
  if (/\b(gloves?)\b/.test(tag)) return term('gloves');
  if (/\b(overalls?|overall skirt)\b/.test(tag)) return term('overalls');
  if (/\b(camisole)\b/.test(tag)) return term('camisole');
  if (/\b(tank ?top|vest)\b/.test(tag)) return term('tank-top');
  if (/\b(uniform|serafuku|maid uniform|naval uniform|military uniform|tennis uniform|basketball uniform)\b/.test(tag)) {
    return term('uniform');
  }
  if (/\b(kimono|yukata|naked kimono)\b/.test(tag)) return term('kimono');
  if (/\b(dress violently torn apart|torn fabric scraps? hanging|fabric scraps? hanging|torn dress remnants?)\b/.test(tag)) {
    return 'dress:torn';
  }
  if (/\b(dress|skirt)\b/.test(tag)) return term('dress');
  if (/\b(shirt|blouse|crop top|cropped shirt|halter top)\b/.test(tag)) return term('shirt');
  if (/\b(jacket|coat|hoodie|hooded jacket|blazer|suit)\b/.test(tag)) {
    return term('outerwear');
  }
  if (/\b(shorts|pants|trousers|buruma)\b/.test(tag)) return term('pants');
  if (/\b(thighhighs?|pantyhose|stockings?|socks?)\b/.test(tag)) {
    return term('legwear');
  }
  if (/\b(shoes?|boots?|sneakers?|heels?)\b/.test(tag)) return term('footwear');
  return '';
}

function visualReplacementModifiersForStageKey(tag, allTags = []) {
  const modifiers = [];
  const add = (key, pattern) => {
    if (pattern.test(tag)) modifiers.push(key);
  };
  add('dark-blue', /\bdark blue\b/);
  add('light-blue', /\blight ?blue\b/);
  add('black', /\bblack\b/);
  add('white', /\bwhite\b/);
  add('pink', /\bpink\b/);
  add('red', /\bred\b/);
  add('blue', /\bblue\b/);
  add('green', /\bgreen\b/);
  add('yellow', /\byellow\b/);
  add('purple', /\bpurple\b/);
  add('brown', /\bbrown\b/);
  add('gray', /\bgr[ae]y\b/);
  add('gold', /\bgold(?:en)?\b/);
  add('orange', /\borange\b/);
  add('lace', /\blace|lacy\b/);
  add('satin', /\bsatin\b/);
  add('silk', /\bsilk|silky\b/);
  add('leather', /\bleather\b/);
  add('latex', /\blatex\b/);
  add('sheer', /\bsheer|see[- ]through|transparent\b/);
  add('fishnet', /\bfishnet|mesh\b/);
  add('frilled', /\bfrill|frilled|frilly|ruffled\b/);
  add('striped', /\bstriped|stripes\b/);
  add('plaid', /\bplaid|checkered\b/);
  add('floral', /\bfloral|flower print\b/);
  add('ribboned', /\bribbon|bow\b/);
  add('aside', /\b(aside|pulled aside|pull aside|swimsuit pull|bikini pull|panty pull|panties pull|bra pull|leotard aside|bikini bottom aside|panties aside|swimsuit aside|shirt aside|skirt aside)\b/);
  add('lifted', /\b(bikini top lift|top lift|shirt lift|skirt lift|dress lift|lifted skirt|lifted dress|lifted shirt|lifted bra)\b/);
  add('open', /\b(open shorts|opened shorts|shorts open|open pants|opened pants|pants open|open shirt|opened shirt|shirt open|open_shorts|open_shirt)\b/);
  add('under-skirt', /\bunder skirt\b/);
  if (hasTornReplacementEvidence(tag)) modifiers.push('torn');
  if (
    /\b(bunny suit|bunny girl outfit|bunny outfit)\b/.test(tag) &&
    !modifiers.some(isColorReplacementModifierForStageKey)
  ) {
    const contextualColor = contextualBunnySuitColorForStageKey(allTags);
    if (contextualColor) modifiers.push(contextualColor);
  }
  return uniqueExact(modifiers);
}

function isColorReplacementModifierForStageKey(modifier) {
  return new Set([
    'dark-blue',
    'light-blue',
    'black',
    'white',
    'pink',
    'red',
    'blue',
    'green',
    'yellow',
    'purple',
    'brown',
    'gray',
    'gold',
    'orange',
  ]).has(modifier);
}

function contextualBunnySuitColorForStageKey(allTags) {
  const tags = uniqueExact(
    allTags.map(normalizedTagKey).filter((tag) => tag.length > 0),
  );
  const colors = [
    ['dark-blue', /\bdark blue\b/],
    ['light-blue', /\blight ?blue\b/],
    ['black', /\bblack\b/],
    ['white', /\bwhite\b/],
    ['pink', /\bpink\b/],
    ['red', /\bred\b/],
    ['blue', /\bblue\b/],
    ['green', /\bgreen\b/],
    ['yellow', /\byellow\b/],
    ['purple', /\bpurple\b/],
    ['brown', /\bbrown\b/],
    ['gray', /\bgr[ae]y\b/],
    ['gold', /\bgold(?:en)?\b/],
    ['orange', /\borange\b/],
  ];
  const candidates = [];
  for (const [key, colorPattern] of colors) {
    const signals = tags.filter((tag) =>
      colorPattern.test(tag) &&
      /\b(stockings?|thighhighs?|socks?|legwear|neck ribbon|ribbon|bow|brooch|arm warmers?|sleeves?|bunny ears?|high heels?|heels?|garter belt|collar)\b/.test(tag),
    );
    const explicitSameSuit = tags.some((tag) =>
      colorPattern.test(tag) &&
      /\b(bunny suit|bunny girl outfit|bunny outfit)\b/.test(tag),
    );
    if (explicitSameSuit || signals.length >= 2) candidates.push(key);
  }
  const uniqueCandidates = uniqueExact(candidates);
  return uniqueCandidates.length === 1 ? uniqueCandidates[0] : '';
}

function isVisualReplacementEvidenceTermForStageKey(tag) {
  return isVisualDisplacementTermForStageKey(tag) ||
    hasTornReplacementEvidence(tag);
}

function hasTornReplacementEvidence(tag) {
  if (/\b(dress violently torn apart|torn fabric scraps? hanging|fabric scraps? hanging|torn dress remnants?)\b/.test(tag)) {
    return true;
  }
  return /\b(torn(?:ed)?|ripped|damaged|shredded)\b/.test(tag) &&
    /\b(panties|underwear|bra|bodysuit|leotard|swimsuit|bikini|dress|skirt|shirt|blouse|halter top|top|jacket|coat|suit|pantyhose|stockings?|thighhighs?|socks?|legwear)\b/.test(tag);
}

function baseReplacementTermForStageKey(term) {
  return stringValue(term).split(':', 1)[0];
}

function replacementModifierSetForStageKey(term) {
  const value = stringValue(term);
  const separator = value.indexOf(':');
  if (separator < 0) return new Set();
  return new Set(value.slice(separator + 1).split('+').filter(Boolean));
}

function isLowerReplacementTermForStageKey(term) {
  const base = baseReplacementTermForStageKey(term);
  return [
    'bikini-bottom',
    'bikini-bottom-only',
    'side-tie-bikini-bottom',
    'underwear',
    'underwear-only',
    'underwear-set',
    'mechanical-underwear',
    'fundoshi',
    'swimsuit-bottom',
    'no-underwear',
    'no-overalls',
    'no-footwear',
    'dress',
    'pants',
    'legwear',
    'footwear',
  ].includes(base);
}

function coreClothingKeyForStageKey({ upper, lower }) {
  const upperCore = uniqueExact(
    upper.filter((term) =>
      [
        'bikini',
        'micro-bikini',
        'maid-bikini',
        'swimsuit',
        'one-piece-swimsuit',
        'school-swimsuit',
        'bra',
        'lace-bra',
        'lingerie-set',
        'babydoll',
        'bunny-suit',
        'bodysuit',
        'leotard',
        'uniform',
        'kimono',
        'dress',
        'shirt',
        'outerwear',
        'gloves',
        'tank-top',
        'camisole',
        'towel',
        'no-bra',
      ].includes(baseReplacementTermForStageKey(term)),
    ),
  ).sort();
  if (upperCore.length > 1 && upperCore.some((term) => baseReplacementTermForStageKey(term) === 'bra')) {
    upperCore.splice(upperCore.findIndex((term) => baseReplacementTermForStageKey(term) === 'bra'), 1);
  }
  if (upperCore.length > 1 && upperCore.some((term) => baseReplacementTermForStageKey(term) === 'bikini')) {
    const swimsuitIndex = upperCore.findIndex((term) => baseReplacementTermForStageKey(term) === 'swimsuit');
    if (swimsuitIndex >= 0) upperCore.splice(swimsuitIndex, 1);
  }
  if (upperCore.length > 1 && upperCore.some((term) => baseReplacementTermForStageKey(term) === 'uniform')) {
    const shirtIndex = upperCore.findIndex((term) => baseReplacementTermForStageKey(term) === 'shirt');
    if (shirtIndex >= 0) upperCore.splice(shirtIndex, 1);
  }
  if (upperCore.length > 1 && upperCore.some((term) => baseReplacementTermForStageKey(term) === 'outerwear')) {
    const shirtIndex = upperCore.findIndex((term) => baseReplacementTermForStageKey(term) === 'shirt');
    if (shirtIndex >= 0) upperCore.splice(shirtIndex, 1);
  }
  const lowerCore = uniqueExact(
    lower.filter((term) =>
      [
        'dress',
        'pants',
        'bikini-bottom',
        'bikini-bottom-only',
        'side-tie-bikini-bottom',
        'fundoshi',
        'swimsuit-bottom',
        'underwear',
        'underwear-only',
        'underwear-set',
        'mechanical-underwear',
        'no-underwear',
        'no-overalls',
        'no-footwear',
      ].includes(baseReplacementTermForStageKey(term)),
    ),
  ).sort();
  if (lowerCore.some((term) => baseReplacementTermForStageKey(term) === 'dress')) {
    for (const term of ['shirt']) {
      const index = upperCore.findIndex((candidate) => baseReplacementTermForStageKey(candidate) === term);
      if (index >= 0) upperCore.splice(index, 1);
    }
  }
  const parts = [];
  if (upperCore.length > 0) parts.push(`upper:${upperCore.join('|')}`);
  if (lowerCore.length > 0) parts.push(`lower:${lowerCore.join('|')}`);
  if (parts.length > 0) return parts.join(';');
  return '';
}

function hasActualTowelForStageTags(tags) {
  const hasBodyTowel = tags.some((tag) =>
    /\b(naked towel|bath towel|towel wrap|wrapped in towel|towel around body|large towel around body|long white towel around body|long towel around body)\b/.test(
      tag,
    ),
  );
  if (hasBodyTowel) return true;
  const hasPlainTowel = tags.some(
    (tag) => tag === 'towel' || /\b(white towel)\b/.test(tag),
  );
  return hasPlainTowel && !tags.some(isHoldingTowelForStageKey);
}

function isActualTowelForStageKey(tag) {
  if (isHoldingTowelForStageKey(tag)) return false;
  return (
    tag === 'towel' ||
    /\b(naked towel|white towel|bath towel|towel wrap|wrapped in towel|towel around body|large towel around body|long white towel around body|long towel around body)\b/.test(
      tag,
    )
  );
}

function isHoldingTowelForStageKey(tag) {
  return /\b(holding towel|cover(?:ing)? mouth with (?:a )?towel|cover(?:ing)? with (?:a )?towel|towel over mouth|towel in mouth)\b/.test(
    tag,
  );
}

function isHeldTowelTag(tag, allTags) {
  if (!/\b(towel|white towel|bath towel)\b/.test(tag)) return false;
  if (/\b(naked towel|bath towel|towel wrap|wrapped in towel|towel around body)\b/.test(tag)) {
    return false;
  }
  return allTags.some(isHoldingTowelForStageKey);
}

function isHeldOrUnwornClothingTag(tag, allTags) {
  if (/\b(pantyhose|stockings?|thighhighs?|socks?|legwear) pull\b/.test(tag)) {
    return true;
  }
  if (
    /\b(bunny suit|bunny girl outfit|bunny outfit)\b/.test(tag) &&
    (/\b(grab|grabbing|holding|pull(?:ed|ing)? down|pulling|pulled)\b/.test(tag) ||
      allTags.some((term) => /\b(nude male|naked male|faceless male|1 male|2 male|male nude)\b/.test(term)))
  ) {
    return true;
  }
  if (isUnwornOrDroppedClothingTag(tag)) return true;
  if (allTags.some((term) => /\b(holding unworn clothes|unworn clothes|discarded clothes|clothes scattered|clothes on floor|scattered around)\b/.test(term))) {
    return /\b(bikini|bikini bottom|side tie bikini bottom|side-tie bikini bottom|panty|panties|underwear|clothes|bra|skirt|pants|dress|shirt|suit|gloves?|stockings?|pantyhose|thighhighs?|socks?|shoes?|boots?)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding .*bikinis?|holding bikini bottom)\b/.test(term))) {
    return /\b(bikini|bikini bottom|side tie bikini bottom|side-tie bikini bottom)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding .*pant(?:y|ies)|holding .*underwear|pant(?:y|ies) in .*hand|look(?:ing)? at pant(?:y|ies)|cum on pant(?:y|ies)|tearing other(?:'?s| s) pant(?:y|ies)|panty pull)\b/.test(term))) {
    return /\b(panty|panties|underwear)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding .*bra|tearing .*bra|tearing clothes with bra|removing other(?:'?s| s) bra)\b/.test(term))) {
    return /\b(bra)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding .*skirt|tearing .*skirt|removing other(?:'?s| s) skirt)\b/.test(term))) {
    return /\b(skirt)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(pull(?:ing)? off girl'?s? .*(?:pantyhose|stockings?|thighhighs?|socks?|legwear)|girl'?s? .*(?:pantyhose|stockings?|thighhighs?|socks?|legwear)|girl pant)\b/.test(term))) {
    return /\b(pantyhose|stockings?|thighhighs?|socks?|legwear)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding pants|pants on head|unbuttoning other(?:'?s| s) shirt|removing other(?:'?s| s) pant(?:y|ies))\b/.test(term))) {
    return /\b(pants|shirt|panty|panties|underwear)\b/.test(tag);
  }
  return false;
}

function isUnwornOrDroppedClothingTag(tag) {
  return /\b(bikini|bikini bottom|side tie bikini bottom|side-tie bikini bottom|panty|panties|underwear|clothes|bra|skirt|pants|dress|shirt|suit|gloves?|stockings?|pantyhose|thighhighs?|socks?|shoes?|boots?)\b/.test(tag) &&
    /\b(unworn|discarded|scattered|on floor|on the floor|around on floor|clothes around waist)\b/.test(tag);
}

function isOtherCharacterClothingActionTag(tag) {
  return /\b(unbuttoning|removing|tearing|pulling|lifting|grabbing)\b.*\b(?:other|another|girl)(?:'?s| s)?\b.*\b(shirt|bra|skirt|dress|pant(?:y|ies)|underwear|bikini|clothes|pantyhose|stockings?|thighhighs?|socks?|legwear)\b/.test(
    tag,
  );
}

function mergeStagesByLabel(stages) {
  if (stages.length <= 1) return stages;
  const byLabel = new Map();
  for (const stage of stages) {
    const labelKey = normalizedStageLabelKey(stage.label) || stage.stage_id;
    const key = `${labelKey}::${stage.semantic_merge_key ?? ''}`;
    const current = byLabel.get(key);
    if (!current) {
      byLabel.set(key, cloneStageForMerge(stage));
      continue;
    }
    mergeStageInto(current, stage);
  }
  const mergedStages = [...byLabel.values()].sort(
    (left, right) =>
      Math.min(...left.frame_indexes) - Math.min(...right.frame_indexes) ||
      normalizedStageLabelKey(left.label).localeCompare(
        normalizedStageLabelKey(right.label),
      ),
  );
  disambiguateDuplicateStageLabels(mergedStages);
  const finalStages = mergeDuplicateLabelsAfterDisambiguation(mergedStages);
  return finalStages.map((stage, index) => {
      const fields = stageFieldsFromStage(stage);
      const { semantic_merge_key, ...stageWithoutMergeKey } = stage;
      return {
        ...stageWithoutMergeKey,
        stage_id: `stage-${index + 1}`,
        appearance_group_id: `appearance-${index + 1}`,
        merge_with_stage_ids: uniqueExact(stage.merge_with_stage_ids).filter(
          (id) => id !== `stage-${index + 1}`,
        ),
        field_reasons: fieldReasons(fields),
        confidence: stage.evidence_terms.length > 0 ? 0.72 : 0.58,
        missing_fields: missingFields(fields),
      };
    });
}

function disambiguateDuplicateStageLabels(stages) {
  if (stages.length <= 1) return stages;
  const duplicateGroups = groupStagesByNormalizedLabel(stages).filter(
    (group) => group.length > 1,
  );
  if (duplicateGroups.length === 0) return stages;

  for (const group of duplicateGroups) {
    for (const stage of group) {
      const suffix = stageLabelDisambiguationSuffix(stage);
      if (!suffix) continue;
      stage.label = appendStageLabelPart(stage.label, suffix);
    }
  }

  const remainingDuplicateGroups = groupStagesByNormalizedLabel(stages).filter(
    (group) => group.length > 1,
  );
  for (const group of remainingDuplicateGroups) {
    const mergeableStages = new Set();
    for (const fieldGroup of groupStagesByFieldEquivalence(group)) {
      if (
        fieldGroup.length > 1 &&
        !hasSemanticReplacementContrastAcrossStages(fieldGroup)
      ) {
        for (const stage of fieldGroup) mergeableStages.add(stage);
      }
    }
    for (const [index, stage] of group.entries()) {
      if (mergeableStages.has(stage)) continue;
      const evidenceSuffix = stageLabelDisambiguationSuffix(stage, {
        allowEvidenceTerms: true,
      });
      const suffix =
        evidenceSuffix && hasNewStageLabelPart(stage.label, evidenceSuffix)
          ? evidenceSuffix
          : `${stage.frame_indexes?.[0] ?? index + 1}\u5e27\u5916\u89c2`;
      stage.label = appendStageLabelPart(stage.label, suffix);
      stage.warnings = uniqueExact([
        ...(stage.warnings ?? []),
        'duplicate_label_disambiguated_by_local_evidence',
      ]);
    }
  }

  return stages;
}

function groupStagesByNormalizedLabel(stages) {
  const groups = new Map();
  for (const stage of stages) {
    const key = normalizedStageLabelKey(stage.label) || stage.stage_id;
    const group = groups.get(key) ?? [];
    group.push(stage);
    groups.set(key, group);
  }
  return [...groups.values()];
}

function appendStageLabelPart(label, suffix) {
  const current = stringValue(label);
  const currentPartKeys = new Set(
    current
      .split(/[\/|,]/g)
      .map(normalizedStageLabelKey)
      .filter(Boolean),
  );
  const missingParts = stringValue(suffix)
    .split(/[\/|,]/g)
    .map((part) => part.trim())
    .filter(Boolean)
    .filter((part) => !currentPartKeys.has(normalizedStageLabelKey(part)));
  if (missingParts.length === 0) return current;
  const normalizedSuffix = normalizedStageLabelKey(missingParts.join(' / '));
  const hasSuffix = current
    .split(/[\/|,]/g)
    .map(normalizedStageLabelKey)
    .some((part) => part === normalizedSuffix);
  if (hasSuffix || normalizedStageLabelKey(current).includes(normalizedSuffix)) {
    return current;
  }
  return `${current} / ${missingParts.join(' / ')}`;
}

function mergeDuplicateLabelsAfterDisambiguation(stages) {
  const byLabel = new Map();
  for (const stage of stages) {
    const labelKey = normalizedStageLabelKey(stage.label) || stage.stage_id;
    const mergeKey = `${labelKey}::${semanticEquivalenceBucketForFinalMerge(
      stage.semantic_merge_key,
    )}`;
    const current = byLabel.get(mergeKey);
    if (!current) {
      byLabel.set(mergeKey, cloneStageForMerge(stage));
      continue;
    }
    mergeStageInto(current, stage);
    current.warnings = uniqueExact([
      ...(current.warnings ?? []),
      'duplicate_label_merged_after_disambiguation',
    ]);
  }
  return mergeEquivalentFieldDuplicateStages([...byLabel.values()]).sort(
    (left, right) =>
      Math.min(...left.frame_indexes) - Math.min(...right.frame_indexes) ||
      normalizedStageLabelKey(left.label).localeCompare(
        normalizedStageLabelKey(right.label),
      ),
  );
}

function mergeEquivalentFieldDuplicateStages(stages) {
  const result = [];
  for (const labelGroup of groupStagesByNormalizedLabel(stages)) {
    if (labelGroup.length <= 1) {
      result.push(...labelGroup);
      continue;
    }
    for (const fieldGroup of groupStagesByFieldEquivalence(labelGroup)) {
      if (
        fieldGroup.length <= 1 ||
        hasSemanticReplacementContrastAcrossStages(fieldGroup)
      ) {
        result.push(...fieldGroup);
        continue;
      }
      const [first, ...rest] = fieldGroup.map(cloneStageForMerge);
      for (const stage of rest) mergeStageInto(first, stage);
      first.warnings = uniqueExact([
        ...(first.warnings ?? []),
        'duplicate_label_merged_by_equivalent_fields',
      ]);
      result.push(first);
    }
  }
  return result;
}

function groupStagesByFieldEquivalence(stages) {
  const groups = new Map();
  for (const stage of stages) {
    const key = stageFieldEquivalenceKeyForFinalMerge(stage);
    const group = groups.get(key) ?? [];
    group.push(stage);
    groups.set(key, group);
  }
  return [...groups.values()];
}

function stageFieldEquivalenceKeyForFinalMerge(stage) {
  return [
    stage.identity,
    stage.upper_body,
    stage.lower_body,
    stage.upper_clothing,
    stage.lower_clothing,
  ]
    .map((value) =>
      splitFieldText(value)
        .map(canonicalFieldTermForEquivalence)
        .filter(Boolean)
        .sort()
        .join('|'),
    )
    .join(';');
}

function canonicalFieldTermForEquivalence(value) {
  const normalized = normalizedTagKey(value);
  if (!normalized) return '';
  if (/\btank ?top\b/.test(normalized)) return 'tank top';
  return normalized;
}

function hasSemanticColorContrastAcrossStages(stages) {
  const signatures = stages.map((stage) =>
    semanticColorSignature(stage.semantic_merge_key),
  );
  const bases = new Set(signatures.flatMap((signature) => [...signature.keys()]));
  for (const base of bases) {
    const variants = uniqueExact(
      signatures
        .map((signature) => signature.get(base) ?? '')
        .filter((value) => value),
    );
    if (variants.length > 1) return true;
  }
  return false;
}

function hasSemanticReplacementContrastAcrossStages(stages) {
  if (hasSemanticColorContrastAcrossStages(stages)) return true;
  const signatures = uniqueExact(
    stages
      .map((stage) =>
        semanticReplacementSignatureForFinalMerge(stage.semantic_merge_key),
      )
      .filter(Boolean),
  );
  return signatures.length > 1;
}

function semanticReplacementSignatureForFinalMerge(key) {
  const normalized = stringValue(key).replace(/^replacement:/, '');
  if (!normalized) return '';
  if (normalized === 'state:towel') return 'state:towel';
  if (normalized === 'state:nude') return 'state:nude';
  if (normalized.startsWith('state:nude-with:')) {
    return `state:nude-with:${criticalSemanticReplacementTerms(
      normalized.slice('state:nude-with:'.length),
    ).join('|')}`;
  }
  for (const state of ['topless', 'bottomless']) {
    const prefix = `state:${state}:`;
    if (normalized === `state:${state}`) return `state:${state}`;
    if (normalized.startsWith(prefix)) {
      const terms = criticalSemanticReplacementTerms(normalized.slice(prefix.length));
      return `state:${state}:${terms.join('|') || 'body'}`;
    }
  }
  return 'nonstate';
}

function criticalSemanticReplacementTerms(text) {
  return uniqueExact(
    stringValue(text)
      .split(/[;|]/g)
      .map((part) => part.replace(/^(?:upper|lower|clothing):/, ''))
      .filter(Boolean)
      .filter((part) => !isWeakSemanticReplacementTerm(part))
      .map((part) => {
        const base = baseReplacementTermForStageKey(part);
        const modifiers = [...replacementModifierSetForStageKey(part)]
          .filter((modifier) => modifier !== 'aside' && modifier !== 'lifted')
          .sort();
        return modifiers.length > 0 ? `${base}:${modifiers.join('+')}` : base;
      }),
  ).sort();
}

function isWeakSemanticReplacementTerm(term) {
  return [
    'footwear',
    'no-footwear',
    'no-upper-clothing',
    'no-lower-clothing',
  ].includes(baseReplacementTermForStageKey(term));
}

function semanticColorSignature(key) {
  const colors = new Set([
    'black',
    'white',
    'pink',
    'red',
    'blue',
    'green',
    'yellow',
    'purple',
    'brown',
    'gray',
    'gold',
    'orange',
    'dark-blue',
    'light-blue',
  ]);
  const signature = new Map();
  const normalized = stringValue(key).replace(/^replacement:/, '');
  for (const rawPart of normalized.split(/[;|]/g)) {
    const part = rawPart.replace(/^(?:upper|lower):/, '');
    const [base, modifierText = ''] = part.split(':');
    if (!base) continue;
    const termColors = modifierText
      .split('+')
      .filter((modifier) => colors.has(modifier))
      .sort();
    if (termColors.length === 0) continue;
    const current = signature.get(base)
      ? signature.get(base).split('+')
      : [];
    signature.set(base, uniqueExact([...current, ...termColors]).sort().join('+'));
  }
  return signature;
}

function semanticEquivalenceBucketForFinalMerge(key) {
  const normalized = stringValue(key).replace(/^replacement:/, '');
  if (!normalized) return 'unknown';
  return normalized
    .split(';')
    .map((part) => canonicalSemanticPartForFinalMerge(part))
    .sort()
    .join(';');
}

function canonicalSemanticPartForFinalMerge(part) {
  return stringValue(part)
    .split('|')
    .filter((piece) => {
      const base = piece.replace(/^(?:upper|lower):/, '').split(':', 1)[0];
      if (hasStrongReplacementModifierForSemanticPiece(piece)) return true;
      if (
        base === 'swimsuit' &&
        /\b(one-piece-swimsuit|school-swimsuit|bikini|micro-bikini|maid-bikini)\b/.test(part)
      ) {
        return false;
      }
      return true;
    })
    .join('|');
}

function hasStrongReplacementModifierForSemanticPiece(piece) {
  const value = stringValue(piece);
  const separator = value.indexOf(':', value.startsWith('upper:') || value.startsWith('lower:') ? value.indexOf(':') + 1 : 0);
  const modifierText = separator >= 0 ? value.slice(separator + 1) : '';
  return /\b(aside|lifted|open|torn|under-skirt)\b/.test(modifierText);
}

function stageLabelDisambiguationSuffix(stage, options = {}) {
  const upperTerms = splitFieldText(stage.upper_clothing);
  const lowerTerms = splitFieldText(stage.lower_clothing);
  const evidenceTerms = options.allowEvidenceTerms
    ? unique([...(stage.evidence_terms ?? [])])
    : [];
  const allTerms = unique([...upperTerms, ...lowerTerms, ...evidenceTerms]);
  const criticalClothingLabel = criticalDuplicateClothingLabel(
    allTerms,
    stage.label,
  );
  if (criticalClothingLabel) return criticalClothingLabel;

  const semanticSuffix = semanticKeyDisambiguationSuffix(stage.semantic_merge_key);
  if (semanticSuffix && hasNewStageLabelPart(stage.label, semanticSuffix)) {
    return semanticSuffix;
  }
  const stateLabel = stateDisambiguationLabelForTerms(allTerms);
  const explicitRemoval = explicitRemovalLabelForTerms(allTerms);
  if (explicitRemoval) return explicitRemoval;

  const lowerLabel = compactSpecificOutfitLabel(lowerTerms);
  if (lowerLabel) return lowerLabel;
  const upperLabel = compactSpecificOutfitLabel(upperTerms);
  if (upperLabel) return upperLabel;
  if (stateLabel) return stateLabel;
  return compactSpecificOutfitLabel(allTerms);
}

function criticalDuplicateClothingLabel(terms, currentLabel) {
  const currentKey = normalizedStageLabelKey(currentLabel);
  const labels = [];
  for (const term of terms) {
    const normalized = normalizedTagKey(term);
    if (
      /\b(black|white|pink|red|blue|green|yellow|purple|brown|gray|grey|gold|orange)\b/.test(
        normalized,
      ) &&
      /\b(panty|panties|underwear|bra|bikini|swimsuit|babydoll|lingerie)\b/.test(
        normalized,
      )
    ) {
      const label = outfitLabelText(term);
      if (label && !currentKey.includes(normalizedStageLabelKey(label))) {
        labels.push(label);
      }
    }
  }
  return uniqueExact(labels).slice(0, 2).join(' / ');
}

function hasNewStageLabelPart(label, suffix) {
  const currentPartKeys = new Set(
    stringValue(label)
      .split(/[\/|,]/g)
      .map(normalizedStageLabelKey)
      .filter(Boolean),
  );
  return stringValue(suffix)
    .split(/[\/|,]/g)
    .map((part) => part.trim())
    .filter(Boolean)
    .some((part) => !currentPartKeys.has(normalizedStageLabelKey(part)));
}

function semanticKeyDisambiguationSuffix(key) {
  const normalized = stringValue(key).replace(/^replacement:/, '');
  if (!normalized) return '';
  if (normalized === 'state:towel') return '\u6d74\u5dfe';
  if (normalized.startsWith('state:')) return stateSemanticKeyLabel(normalized);
  const labels = [];
  for (const rawPart of normalized.split(/[;|]/g)) {
    const part = rawPart.replace(/^clothing:/, '');
    const term = termFromSemanticClothingKey(part);
    if (!term) continue;
    const label = outfitLabelText(term);
    if (label) {
      labels.push({
        label,
        priority: hasStrongReplacementModifierForSemanticPiece(part) ? 1 : 0,
      });
    }
  }
  return uniqueExact(
    labels
      .sort((left, right) => right.priority - left.priority)
      .map((entry) => entry.label),
  )
    .slice(0, 3)
    .join(' / ');
}

function stateSemanticKeyLabel(key) {
  const parts = key.split(':');
  const state = parts[1] ?? '';
  const detail = parts.slice(2).join(':');
  const labels = [];
  if (state === 'topless') labels.push('\u4e0a\u8eab\u88f8\u4f53');
  if (state === 'bottomless') labels.push('\u4e0b\u8eab\u88f8\u4f53');
  if (state === 'nude') labels.push('\u5168\u88f8');
  if (state === 'nude-with') labels.push('\u88f8\u4f53');
  if (detail === 'no-upper-clothing') labels.push('\u65e0\u4e0a\u8863');
  if (detail === 'no-lower-clothing') labels.push('\u65e0\u4e0b\u88c5');
  for (const rawPart of detail.split(/[|;]/g)) {
    const term = termFromSemanticClothingKey(rawPart);
    if (!term) continue;
    const label = outfitLabelText(term);
    if (label) labels.push(label);
  }
  return uniqueExact(labels).slice(0, 3).join(' / ');
}

function termFromSemanticClothingKey(part) {
  const value = stringValue(part).replace(/^(?:upper|lower):/, '');
  if (!value || value === 'no-upper-clothing' || value === 'no-lower-clothing') {
    return '';
  }
  const separator = value.indexOf(':');
  const base = separator >= 0 ? value.slice(0, separator) : value;
  const modifierText = separator >= 0 ? value.slice(separator + 1) : '';
  const modifiers = modifierText
    .split('+')
    .map((value) => value.replace(/-/g, ' '))
    .filter(Boolean);
  if (base === 'no-underwear') return 'no panties';
  if (base === 'no-bra') return 'no bra';
  if (base === 'no-overalls') return 'no overalls';
  const baseWords = {
    'underwear': 'panties',
    'underwear-only': 'underwear only',
    'underwear-set': 'underwear set',
    'mechanical-underwear': 'mechanical underwear',
    'fundoshi': 'fundoshi',
    'bunny-suit': 'bunny suit',
    'swimsuit-bottom': 'swimsuit',
    'bikini-bottom': 'bikini bottom',
    'bikini-bottom-only': 'bikini bottom only',
    'side-tie-bikini-bottom': 'side tie bikini bottom',
    'micro-bikini': 'micro bikini',
    'maid-bikini': 'maid bikini',
    'one-piece-swimsuit': 'one piece swimsuit',
    'school-swimsuit': 'school swimsuit',
    'lingerie-set': 'lingerie',
    'bodysuit': 'bodysuit',
    'leotard': 'leotard',
    'tank-top': 'tank top',
    'lace-bra': 'lace bra',
    'no-footwear': 'shoes off',
    'outerwear': 'jacket',
    'gloves': 'gloves',
  }[base] ?? base.replace(/-/g, ' ');
  return uniqueExact([...modifiers, baseWords.split(/\s+/).join(' ')]).join(' ');
}

function stateDisambiguationLabelForTerms(terms) {
  const normalized = terms.map(normalizedTagKey);
  if (normalized.some((term) => isActualTowelForStageKey(term))) {
    return '\u6d74\u5dfe';
  }
  if (normalized.some((term) => /\b(bottomless)\b/.test(term))) {
    return '\u4e0b\u8eab\u88f8\u4f53';
  }
  if (normalized.some((term) => /\b(topless|topless female)\b/.test(term))) {
    return '\u4e0a\u8eab\u88f8\u4f53';
  }
  if (normalized.some((term) => /\b(nude|naked|completely nude|no clothes)\b/.test(term))) {
    return '\u5168\u88f8';
  }
  return '';
}

function explicitRemovalLabelForTerms(terms) {
  const normalized = terms.map(normalizedTagKey);
  if (normalized.some((term) => /\b(no panties|no underwear)\b/.test(term))) {
    return '\u65e0\u5185\u88e4';
  }
  if (normalized.some((term) => /\b(no bra)\b/.test(term))) return '\u65e0\u6587\u80f8';
  if (normalized.some((term) => /\b(no overall|no overalls)\b/.test(term))) {
    return '\u65e0\u80cc\u5e26\u88e4';
  }
  if (normalized.some((term) => /\b(no skirt)\b/.test(term))) return '\u65e0\u88d9\u5b50';
  if (normalized.some((term) => /\b(no socks|no stockings|no pantyhose)\b/.test(term))) {
    return '\u65e0\u889c\u5b50';
  }
  if (normalized.some((term) => /\b(no shoes)\b/.test(term))) return '\u65e0\u978b';
  if (normalized.some((term) => /\b(no gloves?)\b/.test(term))) return '\u65e0\u624b\u5957';
  return '';
}

function compactSpecificOutfitLabel(terms) {
  const label = compactChineseOutfitLabel(terms);
  if (!label || label === '\u5e38\u670d' || label === '甯告湇') return '';
  return label;
}

function cloneStageForMerge(stage) {
  return {
    ...stage,
    frame_indexes: sortedInts(stage.frame_indexes ?? []),
    merge_with_stage_ids: uniqueExact(stage.merge_with_stage_ids ?? []),
    evidence_terms: unique(stage.evidence_terms ?? []),
    warnings: uniqueExact(stage.warnings ?? []),
  };
}

function mergeStageInto(target, source) {
  target.frame_indexes = sortedInts([
    ...(target.frame_indexes ?? []),
    ...(source.frame_indexes ?? []),
  ]);
  target.identity = mergeFieldText(target.identity, source.identity);
  target.upper_body = mergeFieldText(target.upper_body, source.upper_body);
  target.lower_body = mergeFieldText(target.lower_body, source.lower_body);
  target.upper_clothing = mergeFieldText(
    target.upper_clothing,
    source.upper_clothing,
  );
  target.lower_clothing = mergeFieldText(
    target.lower_clothing,
    source.lower_clothing,
  );
  target.evidence_terms = unique([
    ...(target.evidence_terms ?? []),
    ...(source.evidence_terms ?? []),
  ]);
  target.merge_with_stage_ids = uniqueExact([
    ...(target.merge_with_stage_ids ?? []),
    source.stage_id,
    ...(source.merge_with_stage_ids ?? []),
  ]);
  target.warnings = uniqueExact([
    ...(target.warnings ?? []),
    ...(source.warnings ?? []),
  ]);
}

function stageFieldsFromStage(stage) {
  return {
    identity: stringValue(stage.identity),
    upperBody: stringValue(stage.upper_body),
    lowerBody: stringValue(stage.lower_body),
    upperClothing: stringValue(stage.upper_clothing),
    lowerClothing: stringValue(stage.lower_clothing),
    evidenceTerms: unique(stage.evidence_terms ?? []),
  };
}

function mergeFieldText(left, right) {
  return unique([...splitFieldText(left), ...splitFieldText(right)]).join(', ');
}

function splitFieldText(value) {
  return stringValue(value)
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
}

function normalizedStageLabelKey(label) {
  const raw = stringValue(label);
  const parts = raw
    .split(/[\/|,，、;；:：]+/g)
    .map((part) => part.replace(/\s+/g, '').trim())
    .filter(Boolean);
  if (parts.length > 1) return parts.sort().join('');
  return raw
    .replace(/\s+/g, '')
    .replace(/[\/|,，、;；:：]+/g, '')
    .trim();
}

function stageSignatureForEntry(entry) {
  const terms = [];
  const upperClothingTerms = [];
  const lowerClothingTerms = [];
  const stateTerms = [];
  const normalizedEntryTags = entry.tags.map(normalizedTagKey).filter(Boolean);
  for (const tag of entry.tags) {
    const normalized = normalizedTagKey(tag);
    if (!normalized) continue;
    if (
      isHeldOrUnwornClothingTag(normalized, normalizedEntryTags) ||
      isHeldTowelTag(normalized, normalizedEntryTags)
    ) {
      continue;
    }
    if (isStageStateTerm(normalized)) {
      const term = stageSignatureTerm(normalized);
      terms.push(term);
      stateTerms.push(term);
      if (term === 'towel' || term === 'no bra') upperClothingTerms.push(term);
      if (term === 'no underwear' || term === 'no overalls') {
        lowerClothingTerms.push(term);
      }
      continue;
    }
    const category = categoryForTag(tag);
    if (
      category === 'upperBody' ||
      category === 'lowerBody' ||
      category === 'upperClothing' ||
      category === 'lowerClothing'
    ) {
      const term = stageSignatureTerm(normalized);
      terms.push(term);
      if (category === 'upperClothing') upperClothingTerms.push(term);
      if (category === 'lowerClothing') lowerClothingTerms.push(term);
    }
  }
  for (const tag of entry.baseTags) {
    const normalized = normalizedTagKey(tag);
    if (isStageContextTerm(normalized)) terms.push(stageSignatureTerm(normalized));
  }
  const uniqueTerms = uniqueExact(terms.filter(Boolean)).sort();
  const bucket = stageSignatureBucket(uniqueTerms);
  return {
    terms: uniqueTerms,
    bucket,
    mergeKey: stageMergeKey({
      bucket,
      stateTerms: uniqueExact(stateTerms.filter(Boolean)).sort(),
      upperClothingTerms: uniqueExact(upperClothingTerms.filter(Boolean)).sort(),
      lowerClothingTerms: uniqueExact(lowerClothingTerms.filter(Boolean)).sort(),
    }),
  };
}

function stageMergeKey({
  bucket,
  stateTerms,
  upperClothingTerms,
  lowerClothingTerms,
}) {
  const state = new Set(stateTerms);
  const replacementUpperClothingTerms = replacementRelevantClothingTerms(
    upperClothingTerms,
  );
  const replacementLowerClothingTerms = replacementRelevantClothingTerms(
    lowerClothingTerms,
  );
  if (state.has('towel')) return 'state:towel';
  if (state.has('bottomless')) {
    return replacementUpperClothingTerms.length > 0
      ? `state:bottomless:${replacementUpperClothingTerms.join('|')}`
      : 'state:bottomless:no-upper-clothing';
  }
  if (state.has('nude')) {
    const clothingTerms = [
      ...replacementUpperClothingTerms,
      ...replacementLowerClothingTerms,
    ];
    return clothingTerms.length > 0
      ? `state:nude-with:${clothingTerms.join('|')}`
      : 'state:nude';
  }
  if (state.has('topless')) {
    return replacementLowerClothingTerms.length > 0
      ? `state:topless:${replacementLowerClothingTerms.join('|')}`
      : 'state:topless:no-lower-clothing';
  }
  const clothingParts = [];
  if (replacementUpperClothingTerms.length > 0) {
    clothingParts.push(`upper:${replacementUpperClothingTerms.join('|')}`);
  }
  if (replacementLowerClothingTerms.length > 0) {
    clothingParts.push(`lower:${replacementLowerClothingTerms.join('|')}`);
  }
  if (clothingParts.length > 0) {
    return `clothing:${clothingParts.join(';')}`;
  }
  return `bucket:${['nude', 'towel', 'underwear', 'swimsuit'].includes(bucket)
    ? bucket
    : 'unspecified'}`;
}

function replacementRelevantClothingTerms(terms) {
  const filtered = terms.filter(
    (term) => {
      const base = baseReplacementTermForStageKey(term);
      return !/\b(gloves?|sleeves?)\b/.test(term) &&
      ![
        'legwear',
        'footwear',
        'no hat',
        'bare shoulders',
        'clothing displaced',
      ].includes(base);
    },
  );
  if (filtered.some((term) => baseReplacementTermForStageKey(term) === 'bikini')) {
    return filtered.filter((term) => baseReplacementTermForStageKey(term) !== 'swimsuit');
  }
  return filtered;
}

function isNonRoleReplacementStateTermForStageKey(normalized) {
  return [
    /\b(nude male'?s? arm|nude male s arm|nude man'?s? arm|nude man s arm|nude boy'?s? arm|nude boy s arm|male'?s? arm|male s arm|man'?s? arm|man s arm|boy'?s? arm|boy s arm|nude arm)\b/,
    /\b(girl panties|girl'?s? .*(?:pantyhose|stockings?|thighhighs?|socks?|legwear)|girl pant|hand bra|hand wedgie|wedgie|hand in panties|hand in another s panties|hand inside .*bikini bottom|holding .*pants|holding another s pants|holding .*pant(?:y|ies)|holding .*bikini|holding .*bra|holding .*skirt|holding bikini bottom|holding unworn clothes|unworn clothes|pant(?:y|ies) in .*hand|look(?:ing)? at pant(?:y|ies)|cum on pant(?:y|ies)|tearing .*bra|tearing .*skirt|tearing other(?:'?s| s) pant(?:y|ies)|tearing clothes with bra|pull(?:ing)? off girl'?s? .*(?:pantyhose|stockings?|thighhighs?|socks?|legwear)|panty pull|(?:pantyhose|stockings?|thighhighs?|socks?|legwear) pull|pants on head|unbuttoning other(?:'?s| s) shirt|removing other(?:'?s| s) bra|removing other(?:'?s| s) skirt|removing other(?:'?s| s) pant(?:y|ies))\b/,
    /\b(hand on skirt|hands on skirt|lifting .*skirt|lifted .*skirt|lifting other s skirt|lifting another s skirt|removing .*top|removing other s top)\b/,
    /\b(pants pull|bikini pull|pulling down .*bikini|hands on bikini|hands on breasts|bikini top pull|hands on bikini top)\b/,
    /\b(grabbing another s (?:jacket|coat|skirt|dress|clothes|pants|panties|bikini)|grabbing girl s underwear|tear .*underwear|poke .*shirt)\b/,
    /\b(lifted .*bra|lifting .*bra|lifting .*dress|dress .*lift|torn .*skirt|torn .*dress|skirt pull|skirt lift)\b/,
    /\b(partially undressed|torn clothes|forced exposure|pussy cutout|breasts? out|face to crotch|undressing another)\b/,
    /\b(bikini aside|swimsuit aside|leotard aside|bra aside|shirt aside|skirt aside|clothes aside|panties aside)\b/,
  ].some((pattern) => pattern.test(normalized));
}

function isStageStateTerm(normalized) {
  if (
    /\b(holding towel|cover(?:ing)? mouth with (?:a )?towel|cover(?:ing)? with (?:a )?towel|towel over mouth|towel in mouth)\b/.test(
      normalized,
    )
  ) {
    return false;
  }
  if (isNonRoleReplacementStateTermForStageKey(normalized)) return false;
  if (/\b(breasts? out)\b/.test(normalized)) return false;
  return /\b(nude|naked|completely nude|topless|topless female|bottomless|no clothes|towel wrap|wrapped in towel|towel around body|large towel around body|long white towel around body|long towel around body|naked towel|white towel|bath towel|no panties|no underwear|no bra|no overall|no overalls|bikini bottom only)\b/.test(
    normalized,
  ) || normalized === 'towel';
}

function isStageContextTerm(normalized) {
  return /\b(bathroom|bath|bathtub|shower|onsen|hot spring|workshop|factory|garage|mechanic|bedroom|bed|locker room)\b/.test(
    normalized,
  );
}

function stageSignatureTerm(normalized) {
  if (
    /\b(holding towel|cover(?:ing)? mouth with (?:a )?towel|cover(?:ing)? with (?:a )?towel|towel over mouth|towel in mouth)\b/.test(
      normalized,
    )
  ) {
    return '';
  }
  if (isNonRoleReplacementStateTermForStageKey(normalized)) return '';
  if (/\b(no bra)\b/.test(normalized)) return 'no bra';
  if (/\b(no panties|no underwear)\b/.test(normalized)) return 'no underwear';
  if (/\b(no overall|no overalls)\b/.test(normalized)) return 'no overalls';
  if (/\b(topless|topless female)\b/.test(normalized)) return 'topless';
  if (/\b(bottomless)\b/.test(normalized)) return 'bottomless';
  if (
    normalized === 'towel' ||
    /\b(towel wrap|wrapped in towel|towel around body|large towel around body|long white towel around body|long towel around body|naked towel|white towel|bath towel)\b/.test(
      normalized,
    )
  ) {
    return 'towel';
  }
  if (/\b(nude|naked|completely nude|no clothes)\b/.test(normalized)) {
    return 'nude';
  }
  if (isHardNonRoleTerm(normalized)) return '';
  if (/\b(overalls?|overall skirt)\b/.test(normalized)) return 'overalls';
  if (/\b(babydoll|baby doll|negligee|chemise|teddy)\b/.test(normalized)) {
    return 'babydoll';
  }
  if (/\b(lingerie|sleepwear|nightgown)\b/.test(normalized)) {
    return 'lingerie';
  }
  if (/\b(tank ?top)\b/.test(normalized)) return 'tank top';
  if (/\b(camisole)\b/.test(normalized)) return 'camisole';
  if (/\b(bikini bottom only)\b/.test(normalized)) return 'bikini bottom only';
  if (/\b(bikini bottoms?|side tie bikini bottom|side-tie bikini bottom)\b/.test(normalized)) {
    return 'bikini bottom';
  }
  if (/\b(panties|underwear)\b/.test(normalized)) return 'underwear';
  if (/\b(bikini)\b/.test(normalized)) return 'bikini';
  if (/\b(swimsuit)\b/.test(normalized)) return 'swimsuit';
  if (/\b(dress|skirt)\b/.test(normalized)) return 'dress';
  if (/\b(uniform|serafuku)\b/.test(normalized)) return 'uniform';
  if (/\b(hoodie|hooded jacket|jacket|coat)\b/.test(normalized)) {
    return 'outerwear';
  }
  if (/\b(breasts? out)\b/.test(normalized)) return '';
  if (/\b(no hat)\b/.test(normalized)) return 'no hat';
  if (/\b(bare shoulders|strap slip|breast out|clothes lift|shirt lift|dress lift|open clothes|panties aside)\b/.test(normalized)) {
    return 'clothing displaced';
  }
  return normalized;
}

function stageSignatureBucket(terms) {
  const set = new Set(terms);
  if (set.has('towel')) return 'towel';
  if (set.has('nude')) return 'nude';
  if (set.has('underwear') || set.has('no underwear') || set.has('no bra')) {
    return 'underwear';
  }
  if (set.has('overalls')) return 'overalls';
  if (set.has('tank top')) return 'tank top';
  return terms.join('|') || 'unspecified';
}

function jaccard(left, right) {
  const leftSet = new Set(left);
  const rightSet = new Set(right);
  if (leftSet.size === 0 && rightSet.size === 0) return 1;
  let intersection = 0;
  for (const value of leftSet) {
    if (rightSet.has(value)) intersection += 1;
  }
  return intersection / (leftSet.size + rightSet.size - intersection);
}

function isIdentityTermAllowedForGroup(group, tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return false;
  const groupIdentity = sanitizeIdentityForRole(group.identity);
  const termIdentity = sanitizeIdentityForRole(identityForTags([tag]));
  if (termIdentity.concreteKey) {
    if (!groupIdentity.concreteKey) return true;
    return characterIdentityKey(termIdentity) === characterIdentityKey(groupIdentity);
  }
  if (groupIdentity.concreteKey) {
    const generics = termIdentity.generic ?? [];
    if (generics.some((term) => !isBasicGenericIdentity(term))) return false;
  }
  const termGender = genderForIdentityTerm(normalized);
  if (!termGender) return true;
  const preferredGender = preferredIdentityGender(groupIdentity);
  if (!preferredGender) return true;
  return termGender === preferredGender;
}

function fieldsForGroup(group) {
  const counts = {
    identity: new Map(),
    upperBody: new Map(),
    lowerBody: new Map(),
    upperClothing: new Map(),
    lowerClothing: new Map(),
    nonRole: new Map(),
    context: new Map(),
  };
  for (const entry of group.frameTags) {
    const normalizedEntryTags = entry.tags.map(normalizedTagKey).filter(Boolean);
    for (const tag of entry.tags) {
      const normalized = normalizedTagKey(tag);
      if (
        (isVisualDisplacementTermForStageKey(normalized) &&
          !hasTornReplacementEvidence(normalized)) ||
        isHeldOrUnwornClothingTag(normalized, normalizedEntryTags) ||
        isHeldTowelTag(normalized, normalizedEntryTags)
      ) {
        addTerm(counts.nonRole, tag);
        continue;
      }
      const category = categoryForTag(tag);
      if (category === 'identity' && !isIdentityTermAllowedForGroup(group, tag)) {
        addTerm(counts.nonRole, tag);
        continue;
      }
      addTerm(
        counts[category],
        category === 'identity'
          ? identityFieldTermForTag(tag)
          : roleFieldTermForCategory(tag, category),
      );
    }
    for (const tag of entry.baseTags) {
      const category = categoryForTag(tag);
      if (category === 'context') {
        addTerm(counts.context, tag);
      }
    }
  }
  for (const tag of group.identity.concrete) {
    addTerm(counts.identity, tag, 100000);
  }
  const sanitizedGroupIdentity = sanitizeIdentityForRole(group.identity);
  for (const tag of sanitizedGroupIdentity.generic) {
    if (
      sanitizedGroupIdentity.concreteKey &&
      !isBasicGenericIdentity(tag)
    ) {
      continue;
    }
    addTerm(counts.identity, tag, 90000);
  }

  const frameCount = Math.max(1, group.frames.size);
  const identityTerms = topTerms(counts.identity, 1, 8);
  const upperBodyTerms = topStableTerms(counts.upperBody, frameCount, 12);
  const lowerBodyTerms = topStableTerms(counts.lowerBody, frameCount, 8);
  let upperClothingTerms = topStableTerms(counts.upperClothing, frameCount, 12);
  let lowerClothingTerms = topStableTerms(counts.lowerClothing, frameCount, 12);
  if (group.semanticKey) {
    const replacementKeys = uniqueExact(
      group.frameTags.map((entry) => frameReplacementKeyForStageTags(entry.tags)),
    );
    if (replacementKeys.every((key) => key.includes('no-underwear'))) {
      lowerClothingTerms = lowerClothingTerms.filter(
        (term) => !['underwear', 'underwear-only'].includes(
          baseReplacementTermForStageKey(
            replacementClothingTermForStageKey(normalizedTagKey(term), []) ||
              normalizedTagKey(term),
          ),
        ),
      );
    }
    if (replacementKeys.every((key) => key.includes('no-bra'))) {
      upperClothingTerms = upperClothingTerms.filter(
        (term) => !['bra', 'lace-bra'].includes(
          baseReplacementTermForStageKey(
            replacementClothingTermForStageKey(normalizedTagKey(term), []) ||
              normalizedTagKey(term),
          ),
        ),
      );
    }
    if (replacementKeys.every((key) => key === 'state:towel')) {
      upperClothingTerms = upperClothingTerms.filter((term) =>
        isActualTowelForStageKey(normalizedTagKey(term)),
      );
      lowerClothingTerms = [];
    } else if (replacementKeys.every((key) => key === 'state:nude')) {
      upperClothingTerms = [];
      lowerClothingTerms = [];
    } else if (replacementKeys.every((key) => key.startsWith('state:bottomless'))) {
      lowerClothingTerms = lowerClothingTerms.filter((term) => {
        const replacement =
          replacementClothingTermForStageKey(normalizedTagKey(term), []) ||
          normalizedTagKey(term);
        return [
          'legwear',
          'underwear',
          'underwear-only',
          'underwear-set',
          'bikini-bottom',
          'bikini-bottom-only',
          'side-tie-bikini-bottom',
          'no-underwear',
        ].includes(baseReplacementTermForStageKey(replacement));
      });
    } else if (replacementKeys.every((key) => key.startsWith('state:topless'))) {
      upperClothingTerms = upperClothingTerms.filter((term) =>
        /\b(gloves?|sleeves?|towel)\b/.test(normalizedTagKey(term)),
      );
    }
  }
  const evidenceTerms = unique([
    ...identityTerms,
    ...upperBodyTerms,
    ...lowerBodyTerms,
    ...upperClothingTerms,
    ...lowerClothingTerms,
  ]);
  return {
    identityTerms,
    upperBodyTerms,
    lowerBodyTerms,
    upperClothingTerms,
    lowerClothingTerms,
    contextTerms: topTerms(counts.context, 1, 20),
    nonRoleTerms: topTerms(counts.nonRole, 1, 20),
    identity: identityTerms.join(', '),
    upperBody: upperBodyTerms.join(', '),
    lowerBody: lowerBodyTerms.join(', '),
    upperClothing: upperClothingTerms.join(', '),
    lowerClothing: lowerClothingTerms.join(', '),
    evidenceTerms,
  };
}

function isVisualDisplacementTermForStageKey(normalized) {
  return /\b(aside|pulled aside|pull aside|swimsuit pull|bikini pull|panty pull|panties pull|bra pull|leotard aside|bikini bottom aside|panties aside|swimsuit aside|shirt aside|skirt aside|bikini top lift|top lift|shirt lift|skirt lift|dress lift|open shorts|open shirt|open_shorts|open_shirt|shoes? off|shoe removed|shoes removed)\b/.test(
    normalized,
  );
}

function identityFieldTermForTag(tag) {
  const normalized = normalizedTagKey(tag);
  return genericIdentityMap[normalized]?.tag ?? tag;
}

function roleFieldTermForCategory(tag, category) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return tag;
  const color = firstColorForRoleFieldTerm(normalized);
  const prefix = color ? `${color} ` : '';
  if (category === 'upperBody' && /\bglowing vine(?: like)? dendro tattoo\b/.test(normalized)) {
    return 'glowing vine dendro tattoo';
  }
  if (category === 'lowerClothing' && hasTornReplacementEvidence(normalized)) {
    if (/\b(pantyhose|stockings?|thighhighs?|socks?|legwear)\b/.test(normalized)) {
      return `${prefix}torn pantyhose`.trim();
    }
    if (/\b(panties|underwear|briefs)\b/.test(normalized)) {
      return `${prefix}torn underwear`.trim();
    }
    if (/\b(bikini bottoms?|bikini bottom)\b/.test(normalized)) {
      return `${prefix}torn bikini bottom`.trim();
    }
    if (/\b(skirt)\b/.test(normalized)) return `${prefix}torn skirt`.trim();
    if (/\b(pants|shorts|trousers)\b/.test(normalized)) {
      return `${prefix}torn pants`.trim();
    }
  }
  if (category === 'upperClothing' && hasTornReplacementEvidence(normalized)) {
    if (/\b(bodysuit)\b/.test(normalized)) return `${prefix}torn bodysuit`.trim();
    if (/\b(leotard)\b/.test(normalized)) return `${prefix}torn leotard`.trim();
    if (/\b(swimsuit|bikini)\b/.test(normalized)) return `${prefix}torn swimsuit`.trim();
    if (/\b(bra)\b/.test(normalized)) return `${prefix}torn bra`.trim();
    if (/\b(dress)\b/.test(normalized)) return `${prefix}torn dress`.trim();
    if (/\b(shirt|blouse|halter top|top)\b/.test(normalized)) return `${prefix}torn shirt`.trim();
    if (/\b(jacket|coat|suit)\b/.test(normalized)) return `${prefix}torn outerwear`.trim();
  }
  return tag;
}

function firstColorForRoleFieldTerm(normalized) {
  for (const color of [
    'dark blue',
    'light blue',
    'black',
    'white',
    'pink',
    'red',
    'blue',
    'green',
    'yellow',
    'purple',
    'brown',
    'gray',
    'grey',
    'gold',
    'golden',
    'orange',
  ]) {
    const pattern = new RegExp(`\\b${color.replace(/\s+/g, '\\s+')}\\b`);
    if (!pattern.test(normalized)) continue;
    if (color === 'grey') return 'gray';
    if (color === 'golden') return 'gold';
    return color.replace(/\s+/g, '-');
  }
  return '';
}

function displayNameForGroup(group, identityTerms) {
  const sanitized = sanitizeIdentityForRole(group.identity);
  const genericPrimary =
    group.key === 'generic:male'
      ? 'male'
      : sanitized.generic.find((term) => !isBasicGenericIdentity(term)) ||
        sanitized.generic[0];
  const primary =
    displayIdentityPrimary(sanitized) ||
    genericPrimary ||
    identityTerms[0] ||
    'role';
  const translated = translate(primary);
  const fallback = translated.fallback;
  return {
    name:
      translated.text && translated.text !== primary
        ? `${primary} / ${translated.text}`
        : `${primary} / ${fallbackDisplay(primary)}`,
    fallback,
  };
}

function displayIdentityPrimary(identity) {
  if (!identity?.concrete?.length) return '';
  if ((identity.variantTags ?? []).length <= 1) return identity.concrete[0];
  const parsed = parseCharacterTag(identity.concrete[0]);
  const canonical = parsed.canonicalName || identity.canonicalName;
  const franchise = parsed.franchise || identity.franchise;
  if (!canonical) return identity.concrete[0];
  return franchise ? `${canonical} (${franchise})` : canonical;
}

function stageLabelForGroup(group, fields) {
  const labelStateTerms = uniqueExact(
    group.frameTags.flatMap((entry) => entry.tags ?? []),
  )
    .map(normalizedTagKey)
    .filter(isLabelStateTerm);
  const all = [
    ...fields.upperClothingTerms,
    ...fields.lowerClothingTerms,
    ...fields.upperBodyTerms,
    ...fields.lowerBodyTerms,
    ...fields.contextTerms,
    ...labelStateTerms,
  ].map(normalizedTagKey);
  const has = (pattern) => all.some((tag) => pattern.test(tag));
  const hasActualTowelState = group.frameTags.some((entry) =>
    hasActualTowelForStageTags(entry.tags.map(normalizedTagKey).filter(Boolean)),
  );
  const context = contextLabel(fields.contextTerms);
  let label = '';
  if (has(/\b(workshop|factory|garage|maintenance|mechanic|wrench)\b/)) {
    label = '车间工装';
  } else if (has(/\b(bathroom|bath|bathtub|shower|onsen|hot spring|locker room)\b/) &&
      has(/\b(nude|naked|topless|bottomless|no clothes)\b/)) {
    label = `${context || '浴室'}裸体`;
  } else if (has(/\b(nude|naked|completely nude|topless|bottomless)\b/)) {
    label = context ? `${context}裸体` : '裸体';
  } else if (has(/\b(school uniform|sailor uniform|serafuku)\b/)) {
    label =
      compactChineseOutfitLabel([
        ...fields.upperClothingTerms,
        ...fields.lowerClothingTerms,
      ]) || (context ? `${context}校服` : '校服');
  } else if (has(/\b(swimsuit|bikini|school swimsuit|one-piece swimsuit)\b/)) {
    label =
      compactChineseOutfitLabel([
        ...fields.upperClothingTerms,
        ...fields.lowerClothingTerms,
      ]) || (context ? `${context}泳装` : '泳装');
  } else if (has(/\b(maid|maid outfit)\b/)) {
    label =
      compactChineseOutfitLabel([
        ...fields.upperClothingTerms,
        ...fields.lowerClothingTerms,
      ]) || '女仆装';
  } else if (has(/\b(kimono|yukata|hakama)\b/)) {
    label =
      compactChineseOutfitLabel([
        ...fields.upperClothingTerms,
        ...fields.lowerClothingTerms,
      ]) || '和服';
  } else if (hasActualTowelState) {
    label = context ? `${context}浴巾` : '浴巾';
  } else if (has(/\b(hood|hoodie|hooded jacket|jacket|coat)\b/)) {
    label =
      compactChineseOutfitLabel([
        ...fields.upperClothingTerms,
        ...fields.lowerClothingTerms,
      ]) || '外套';
  } else if (fields.upperClothingTerms.length || fields.lowerClothingTerms.length) {
    label = compactChineseOutfitLabel([
      ...fields.upperClothingTerms,
      ...fields.lowerClothingTerms,
    ]);
  }
  const hasTowelState = hasActualTowelState;
  const hasExplicitToplessState = has(/\b(topless|topless female)\b/);
  const hasToplessState = hasExplicitToplessState;
  const hasBottomlessState = has(/\b(bottomless)\b/);
  const hasNudeState =
    has(/\b(nude|naked|completely nude|topless|bottomless|no clothes)\b/);
  if (hasTowelState) {
    label = context ? `${context}\u6d74\u5dfe` : '\u6d74\u5dfe';
  } else if (hasToplessState) {
    label =
      fields.lowerClothingTerms.length > 0
        ? `${context || ''}\u4e0a\u8eab\u88f8\u4f53 / ${compactChineseOutfitLabel(fields.lowerClothingTerms)}`
        : `${context || ''}\u4e0a\u8eab\u88f8\u4f53`;
  } else if (hasBottomlessState) {
    label =
      fields.upperClothingTerms.length > 0
        ? `${context || ''}\u4e0b\u8eab\u88f8\u4f53 / ${compactChineseOutfitLabel(fields.upperClothingTerms)}`
        : `${context || ''}\u4e0b\u8eab\u88f8\u4f53`;
  } else if (hasNudeState) {
    const clothingTerms = replacementRelevantClothingTerms([
      ...fields.upperClothingTerms,
      ...fields.lowerClothingTerms,
    ]);
    label = clothingTerms.length > 0
      ? `${context || ''}\u88f8\u4f53 / ${compactChineseOutfitLabel(clothingTerms)}`
      : context ? `${context}\u88f8\u4f53` : '\u88f8\u4f53';
  } else if (
    has(/\b(workshop|factory|garage|maintenance|mechanic)\b/) &&
    has(/\b(overalls?|overall skirt|work clothes|uniform|tank ?top|gloves?)\b/)
  ) {
    label = '\u8f66\u95f4\u5de5\u88c5';
  }
  if (!label) {
    return { label: context ? `${context}常服` : '常服', fallback: true };
  }
  const correctedLabel = correctStateLabelAgainstSource(label, group, fields, context);
  if (correctedLabel !== label) {
    return { label: correctedLabel, fallback: true };
  }
  return { label, fallback: false };
}

function correctStateLabelAgainstSource(label, group, fields, context) {
  const keys = uniqueExact(
    group.frameTags.map((entry) => frameReplacementKeyForStageTags(entry.tags)),
  );
  const stateKeys = keys.filter((key) => key.startsWith('state:'));
  const allStateKeys =
    stateKeys.length > 0 && stateKeys.length === keys.length ? stateKeys : keys;
  const allTopless =
    allStateKeys.length > 0 &&
    allStateKeys.every((key) => key.startsWith('state:topless'));
  const allBottomless =
    allStateKeys.length > 0 &&
    allStateKeys.every((key) => key.startsWith('state:bottomless'));
  const allNude =
    allStateKeys.length > 0 &&
    allStateKeys.every((key) => key.startsWith('state:nude'));
  const hasNudeKey = keys.some(
    (key) =>
      key.startsWith('state:nude') ||
      key.startsWith('state:topless') ||
      key.startsWith('state:bottomless'),
  );
  const hasTowelKey = keys.includes('state:towel');
  if ((/\u4e0a\u8eab\u88f8\u4f53/.test(label) || /涓婅韩瑁镐綋/.test(label)) && allBottomless) {
    return label
      .replace(/\u4e0a\u8eab\u88f8\u4f53/g, '\u4e0b\u8eab\u88f8\u4f53')
      .replace(/涓婅韩瑁镐綋/g, '\u4e0b\u8eab\u88f8\u4f53');
  }
  if ((/\u4e0b\u8eab\u88f8\u4f53/.test(label) || /涓嬭韩瑁镐綋/.test(label)) && allTopless) {
    return label
      .replace(/\u4e0b\u8eab\u88f8\u4f53/g, '\u4e0a\u8eab\u88f8\u4f53')
      .replace(/涓嬭韩瑁镐綋/g, '\u4e0a\u8eab\u88f8\u4f53');
  }
  if (
    allNude &&
    (/\u4e0a\u8eab\u88f8\u4f53|\u4e0b\u8eab\u88f8\u4f53/.test(label) ||
      /涓婅韩瑁镐綋|涓嬭韩瑁镐綋/.test(label))
  ) {
    return context ? `${context}\u88f8\u4f53` : '\u88f8\u4f53';
  }
  if (/浴巾/.test(label) && !hasTowelKey) {
    return fallbackStageLabel(fields, context);
  }
  if (/裸体/.test(label) && !hasNudeKey) {
    return fallbackStageLabel(fields, context);
  }
  return label;
}

function fallbackStageLabel(fields, context) {
  const clothingTerms = [
    ...fields.upperClothingTerms,
    ...fields.lowerClothingTerms,
  ];
  if (clothingTerms.length > 0) return compactChineseOutfitLabel(clothingTerms);
  return context ? `${context}\u5e38\u670d` : '\u5e38\u670d';
}

function isLabelStateTerm(normalized) {
  if (isHoldingTowelLabelTerm(normalized)) return false;
  if (isNonRoleReplacementStateTermForStageKey(normalized)) return false;
  if (/\b(breasts? out)\b/.test(normalized)) return false;
  return /\b(nude|naked|completely nude|topless|topless female|bottomless|no clothes|towel wrap|wrapped in towel|towel around body|large towel around body|long white towel around body|long towel around body|naked towel|white towel|bath towel|no panties|no underwear|no overall|no overalls|bikini bottom only)\b/.test(
    normalized,
  ) || normalized === 'towel';
}

function isActualTowelLabelTerm(normalized) {
  if (isHoldingTowelLabelTerm(normalized)) return false;
  return normalized === 'towel' ||
    /\b(towel wrap|wrapped in towel|towel around body|large towel around body|long white towel around body|long towel around body|naked towel|white towel|bath towel)\b/.test(
      normalized,
    );
}

function isHoldingTowelLabelTerm(normalized) {
  return /\b(holding towel|cover(?:ing)? mouth with (?:a )?towel|cover(?:ing)? with (?:a )?towel|towel over mouth|towel in mouth)\b/.test(
    normalized,
  );
}

function contextLabel(terms) {
  const normalized = terms.map(normalizedTagKey).join(', ');
  const preciseLabels = [];
  if (/\b(bathroom|bath|bathtub|shower)\b/.test(normalized)) preciseLabels.push('浴室');
  if (/\b(onsen|hot spring)\b/.test(normalized)) preciseLabels.push('温泉');
  if (/\b(workshop|factory|garage|maintenance|mechanic)\b/.test(normalized)) {
    preciseLabels.push('车间');
  }
  if (/\b(school|classroom|campus)\b/.test(normalized)) preciseLabels.push('校园');
  if (/\b(train|subway|station)\b/.test(normalized)) preciseLabels.push('电车');
  if (/\b(street|city|outdoors)\b/.test(normalized)) preciseLabels.push('街头');
  if (/\b(bedroom|bed)\b/.test(normalized)) preciseLabels.push('卧室');
  const uniquePreciseLabels = uniqueExact(preciseLabels);
  if (uniquePreciseLabels.length > 1) return '';
  if (/\b(bathroom|bath|bathtub|shower)\b/.test(normalized)) return '浴室';
  if (/\b(onsen|hot spring)\b/.test(normalized)) return '温泉';
  if (/\b(workshop|factory|garage|maintenance|mechanic)\b/.test(normalized)) {
    return '车间';
  }
  if (/\b(school|classroom|campus)\b/.test(normalized)) return '校园';
  if (/\b(train|subway|station)\b/.test(normalized)) return '电车';
  if (/\b(street|city|outdoors)\b/.test(normalized)) return '街头';
  if (/\b(bedroom|bed)\b/.test(normalized)) return '卧室';
  return '';
}

function compactChineseOutfitLabel(terms) {
  const byKind = new Map();
  const order = [];
  for (const term of terms) {
    const label = outfitLabelText(term);
    if (!label) continue;
    const kind = outfitLabelKind(term, label);
    const current = byKind.get(kind);
    if (!current) {
      byKind.set(kind, { term, label });
      order.push(kind);
    } else if (outfitLabelSpecificity(term, label) > outfitLabelSpecificity(current.term, current.label)) {
      byKind.set(kind, { term, label });
    }
  }
  const translatedAll = order
    .map((kind) => byKind.get(kind)?.label)
    .filter(Boolean);
  const removalLabels = translatedAll.filter((label) => /^\u65e0/.test(label));
  const translated = uniqueExact([
    ...removalLabels,
    ...translatedAll.filter((label) => !/^\u65e0/.test(label)),
  ]).slice(0, 3);
  if (translated.length === 0) return '常服';
  return translated.join(' / ');
}

function outfitLabelSpecificity(term, label) {
  const normalized = normalizedTagKey(term);
  let score = label.length;
  if (colorPrefix(normalized)) score += 20;
  if (/\b(one[- ]piece|highleg|side[- ]tie|intricate|lace|lingerie|babydoll|baby doll|satin|silk|leather|latex|sheer|armored|cropped|hooded|frilled|detachable)\b/.test(normalized)) {
    score += 10;
  }
  if (/\b(no |only )\b/.test(normalized)) score += 4;
  return score;
}

function outfitLabelKind(term, label) {
  const normalized = normalizedTagKey(term);
  if (/\b(no bra)\b/.test(normalized)) return 'no-bra';
  if (/\b(no panties|no underwear)\b/.test(normalized)) return 'no-underwear';
  if (/\b(no overall|no overalls)\b/.test(normalized)) return 'no-overalls';
  if (isActualTowelForStageKey(normalized)) return 'towel';
  if (/\b(bikini bottom|side tie bikini bottom|side-tie bikini bottom)\b/.test(normalized)) return 'bikini-bottom';
  if (/\b(fundoshi|loincloth)\b/.test(normalized)) return 'fundoshi';
  if (/\b(swimsuit-bottom|male\b.*\bswimsuit)\b/.test(normalized)) return 'swimsuit-bottom';
  if (/\b(bikini)\b/.test(normalized)) return 'bikini';
  if (/\b(swimsuit)\b/.test(normalized)) return 'swimsuit';
  if (/\b(bunny suit|bunny girl outfit|bunny outfit)\b/.test(normalized)) return 'bunny-suit';
  if (/\b(babydoll|baby doll|negligee|chemise|teddy)\b/.test(normalized)) return 'babydoll';
  if (/\b(lingerie|sleepwear|nightgown)\b/.test(normalized)) return 'lingerie';
  if (/\b(leotard)\b/.test(normalized)) return 'leotard';
  if (/\b(dress|kimono|yukata|hakama)\b/.test(normalized)) return 'dress';
  if (/\b(skirt)\b/.test(normalized)) return 'skirt';
  if (/\b(jacket|coat|hoodie|outerwear|blazer|suit)\b/.test(normalized)) return 'outerwear';
  if (/\b(shirt|blouse|crop top|cropped shirt|halter top|tank ?top|vest|camisole)\b/.test(normalized)) return 'top';
  if (/\b(bra).*(panties|underwear)\b|\b(panties|underwear).*(bra)\b/.test(normalized)) return 'underwear-set';
  if (/\b(bra)\b/.test(normalized)) return 'bra';
  if (/\b(panties|underwear|briefs)\b/.test(normalized)) return 'underwear';
  if (/\b(pantyhose|thighhighs?|stockings?|socks?)\b/.test(normalized)) return 'legwear';
  if (/\b(shoes?|boots?|sneakers?|heels?)\b/.test(normalized)) return 'footwear';
  if (/\b(gloves?)\b/.test(normalized)) return 'gloves';
  if (/\b(sleeves?)\b/.test(normalized)) return 'sleeves';
  return label;
}

function outfitLabelText(term) {
  const normalized = normalizedTagKey(term);
  const color = colorPrefix(normalized);
  const has = (pattern) => pattern.test(normalized);
  if (has(/\b(no panties|no underwear)\b/)) return '\u65e0\u5185\u88e4';
  if (has(/\b(no bra)\b/)) return '\u65e0\u6587\u80f8';
  if (has(/\b(no overall|no overalls)\b/)) return '\u65e0\u80cc\u5e26\u88e4';
  if (has(/\b(no socks|no stockings|no pantyhose)\b/)) return '\u65e0\u889c\u5b50';
  if (has(/\b(no shoes)\b/)) return '\u65e0\u978b';
  if (has(/\b(no gloves?)\b/)) return '\u65e0\u624b\u5957';
  if (has(/\b(no skirt)\b/)) return '\u65e0\u88d9\u5b50';
  if (has(/\b(shoes? off|shoe removed|shoes removed|no footwear)\b/)) {
    return '\u8131\u978b';
  }
  if (has(/\b(aside|pulled aside|pull aside|bikini pull|panty pull|panties pull|bra pull|top lift|shirt lift|skirt lift|dress lift|lifted skirt|lifted dress|lifted shirt|lifted bra|open shorts|opened shorts|shorts open|open pants|opened pants|pants open|open shirt|opened shirt|shirt open)\b/)) {
    if (has(/\b(bikini top)\b/)) return `${color}\u6bd4\u57fa\u5c3c\u4e0a\u88c5\u63c0\u8d77`;
    if (has(/\b(bikini bottom|side tie bikini bottom|side-tie bikini bottom)\b/)) {
      return `${color}\u6bd4\u57fa\u5c3c\u4e0b\u88c5\u79fb\u4f4d`;
    }
    if (has(/\b(bikini)\b/)) return `${color}\u6bd4\u57fa\u5c3c\u79fb\u4f4d`;
    if (has(/\b(swimsuit|swimwear)\b/)) return `${color}\u6cf3\u88c5\u79fb\u4f4d`;
    if (has(/\b(leotard)\b/)) return `${color}\u7d27\u8eab\u8863\u79fb\u4f4d`;
    if (has(/\b(panties|underwear|briefs)\b/)) return `${color}\u5185\u88e4\u79fb\u4f4d`;
    if (has(/\b(bra)\b/)) return `${color}\u6587\u80f8\u79fb\u4f4d`;
    if (has(/\b(shorts|pants|trousers)\b/)) return `${color}\u655e\u5f00\u7684\u88e4\u5b50`;
    if (has(/\b(shirt|blouse)\b/)) return `${color}\u655e\u5f00\u7684\u886c\u886b`;
    if (has(/\b(dress|skirt)\b/)) return `${color}\u88d9\u88c5\u63c0\u8d77`;
  }
  if (has(/\b(babydoll|baby doll)\b/)) return `${color}\u5a03\u5a03\u88c5`;
  if (has(/\b(bunny suit|bunny girl outfit|bunny outfit)\b/)) return `${color}\u5154\u5973\u90ce\u88c5`;
  if (has(/\b(negligee|chemise)\b/)) return `${color}\u540a\u5e26\u7761\u88d9`;
  if (has(/\b(teddy)\b/)) return `${color}\u8fde\u4f53\u5185\u8863`;
  if (has(/\b(lingerie set|underwear set)\b/)) return `${color}\u5185\u8863\u5957\u88c5`;
  if (has(/\b(lingerie)\b/)) return `${color}\u60c5\u8da3\u5185\u8863`;
  if (has(/\b(sleepwear|nightgown)\b/)) return `${color}\u7761\u88d9`;
  if (has(/\b(bra).*(panties|underwear)\b/) || has(/\b(panties|underwear).*(bra)\b/)) {
    return `${color}\u5185\u8863\u5957\u88c5`;
  }
  if (has(/\b(micro bikini)\b/)) return `${color}\u5fae\u578b\u6bd4\u57fa\u5c3c`;
  if (has(/\b(maid bikini)\b/)) return `${color}\u5973\u4ec6\u6bd4\u57fa\u5c3c`;
  if (has(/\b(frilled|frill|ruffled)\b/) && has(/\b(bikini)\b/)) {
    return `${color}\u8377\u53f6\u8fb9\u6bd4\u57fa\u5c3c`;
  }
  if (has(/\b(side tie bikini bottom|side-tie bikini bottom)\b/)) {
    return `${color}\u4fa7\u7cfb\u5e26\u6bd4\u57fa\u5c3c\u4e0b\u88c5`;
  }
  if (has(/\b(fundoshi|loincloth)\b/)) return `${color}\u515c\u88c6\u5e03`;
  if (has(/\b(swimsuit-bottom|male\b.*\bswimsuit)\b/)) return `${color}\u6cf3\u88e4`;
  if (has(/\b(bikini bottom|bikini bottoms)\b/)) return `${color}\u6bd4\u57fa\u5c3c\u4e0b\u88c5`;
  if (has(/\b(bikini)\b/)) return `${color}\u6bd4\u57fa\u5c3c`;
  if (has(/\b(old school swimsuit|school swimsuit)\b/)) return `${color}\u5b66\u6821\u6cf3\u88c5`;
  if (has(/\b(one piece swimsuit|one-piece swimsuit)\b/)) return `${color}\u8fde\u4f53\u6cf3\u88c5`;
  if (has(/\b(swimsuit|swimwear)\b/)) return `${color}\u6cf3\u88c5`;
  if (has(/\b(mechanical panties|mechanical underwear)\b/)) return `${color}\u673a\u68b0\u5185\u88e4`;
  if (has(/\b(bodysuit)\b/)) return `${color}\u8fde\u4f53\u7d27\u8eab\u8863`;
  if (has(/\b(leotard)\b/)) return `${color}\u7d27\u8eab\u8863`;
  if (has(/\b(sheer|see through|see-through|transparent)\b/) && has(/\b(dress|skirt)\b/)) {
    return `${color}\u900f\u89c6\u8fde\u8863\u88d9`;
  }
  if (has(/\b(camisole)\b/)) return `${color}\u540a\u5e26\u80cc\u5fc3`;
  if (has(/\b(tank ?top|vest)\b/)) return `${color}\u80cc\u5fc3`;
  if (has(/\b(lace bra)\b/)) return `${color}\u857e\u4e1d\u6587\u80f8`;
  if (has(/\b(bra)\b/)) return `${color}\u6587\u80f8`;
  if (has(/\b(underwear only)\b/)) return `${color}\u4ec5\u5185\u8863`;
  if (has(/\b(panties|underwear|briefs)\b/)) return `${color}\u5185\u88e4`;
  const negate = (label) => `无${label}`;
  const only = (label) => `仅${label}`;
  if (isActualTowelForStageKey(normalized)) return `${color}浴巾`;
  if (has(/\b(no panties|no underwear)\b/)) return negate('内裤');
  if (has(/\b(no bra)\b/)) return negate('文胸');
  if (has(/\b(no overall|no overalls)\b/)) return negate('背带裙');
  if (has(/\b(no socks|no stockings|no pantyhose)\b/)) return negate('袜子');
  if (has(/\b(no shoes)\b/)) return negate('鞋');
  if (has(/\b(no gloves?)\b/)) return negate('手套');
  if (has(/\b(no skirt)\b/)) return negate('裙子');
  const translated = translate(term);
  if (!translated.fallback && translated.text) return translated.text;
  if (has(/\b(bra).*(panties|underwear)\b/) || has(/\b(panties|underwear).*(bra)\b/)) {
    return `${color}内衣套装`;
  }
  if (has(/\b(only shirt)\b/)) return only('衬衫');
  if (has(/\b(pantyhose only)\b/)) return only('连裤袜');
  if (has(/\b(underwear only)\b/)) return only('内衣');
  if (has(/\b(bikini top only)\b/)) return only('比基尼上装');
  if (has(/\b(bikini bottom only)\b/)) return only('比基尼下装');
  if (has(/\b(micro bikini)\b/)) return `${color}微型比基尼`;
  if (has(/\b(maid bikini)\b/)) return `${color}女仆比基尼`;
  if (has(/\b(bikini bottom|side tie bikini bottom|side-tie bikini bottom)\b/)) {
    return `${color}比基尼下装`;
  }
  if (has(/\b(bikini)\b/)) return `${color}比基尼`;
  if (has(/\b(old school swimsuit|school swimsuit)\b/)) return `${color}学校泳装`;
  if (has(/\b(one piece swimsuit|one-piece swimsuit)\b/)) return `${color}连体泳装`;
  if (has(/\b(swimsuit)\b/)) return `${color}泳装`;
  if (has(/\b(see through|see-through)\b/) && has(/\b(leotard)\b/)) return `${color}透视紧身衣`;
  if (has(/\b(leotard)\b/)) return `${color}紧身衣`;
  if (has(/\b(cocktail dress|strapless dress|backless dress|glitter dress|sideless dress|dress)\b/)) return `${color}连衣裙`;
  if (has(/\b(skirt)\b/)) return `${color}裙子`;
  if (has(/\b(blazer jacket|suit)\b/)) return `${color}西装`;
  if (has(/\b(jacket|coat|outerwear)\b/)) return `${color}外套`;
  if (has(/\b(hoodie|hooded jacket)\b/)) return `${color}连帽外套`;
  if (has(/\b(sweater)\b/)) return `${color}毛衣`;
  if (has(/\b(blouse)\b/)) return `${color}女式衬衫`;
  if (has(/\b(open shirt|shirt open|open white shirt)\b/)) return `${color}敞开的衬衫`;
  if (has(/\b(shirt|cropped shirt|crop top|crop top overhang)\b/)) return `${color}衬衫`;
  if (has(/\b(camisole)\b/)) return `${color}吊带背心`;
  if (has(/\b(tank ?top|vest)\b/)) return `${color}背心`;
  if (has(/\b(lace bra|bra)\b/)) return `${color}文胸`;
  if (has(/\b(panties|underwear|briefs)\b/)) return `${color}内裤`;
  if (has(/\b(pantyhose)\b/)) return `${color}连裤袜`;
  if (has(/\b(thighhighs?|stockings?)\b/)) return `${color}过膝袜`;
  if (has(/\b(high heels?|heels?)\b/)) return `${color}高跟鞋`;
  if (has(/\b(boots?)\b/)) return `${color}靴子`;
  if (has(/\b(shoes?|sneakers?)\b/)) return `${color}鞋`;
  if (has(/\b(gloves?)\b/)) return `${color}手套`;
  if (has(/\b(sleeves?|elbow sleeve)\b/)) return `${color}袖套`;
  if (has(/\b(garter belt|garter)\b/)) return `${color}吊袜带`;
  if (has(/\b(armor|greek armor)\b/)) return `${color}盔甲`;
  if (has(/\b(apron|naked apron)\b/)) return `${color}围裙`;
  if (has(/\b(uniform|military uniform|naval uniform|basketball uniform|tennis uniform)\b/)) return `${color}制服`;
  return '';
}

function colorPrefix(normalized) {
  const cleanColorLabels = [
    [/\bdark blue\b/, '\u6df1\u84dd\u8272'],
    [/\blight ?blue\b/, '\u6d45\u84dd\u8272'],
    [/\bblack\b/, '\u9ed1\u8272'],
    [/\bwhite\b/, '\u767d\u8272'],
    [/\bpink\b/, '\u7c89\u8272'],
    [/\bred\b/, '\u7ea2\u8272'],
    [/\bblue\b/, '\u84dd\u8272'],
    [/\bgreen\b/, '\u7eff\u8272'],
    [/\byellow\b/, '\u9ec4\u8272'],
    [/\bpurple\b/, '\u7d2b\u8272'],
    [/\bbrown\b/, '\u68d5\u8272'],
    [/\bgray|grey\b/, '\u7070\u8272'],
    [/\bgold(?:en)?\b/, '\u91d1\u8272'],
    [/\borange\b/, '\u6a59\u8272'],
  ];
  for (const [pattern, label] of cleanColorLabels) {
    if (pattern.test(normalized)) return label;
  }
  const colors = [
    [/\bdark blue\b/, '深蓝色'],
    [/\blight ?blue\b/, '浅蓝色'],
    [/\bblack\b/, '黑色'],
    [/\bwhite\b/, '白色'],
    [/\bred\b/, '红色'],
    [/\bblue\b/, '蓝色'],
    [/\bgreen\b/, '绿色'],
    [/\byellow\b/, '黄色'],
    [/\bpink\b/, '粉色'],
    [/\bbrown\b/, '棕色'],
    [/\bgray|grey\b/, '灰色'],
    [/\bgold(?:en)?\b/, '金色'],
    [/\borange\b/, '橙色'],
    [/\bpurple\b/, '紫色'],
  ];
  for (const [pattern, label] of colors) {
    if (pattern.test(normalized)) return label;
  }
  return '';
}

function categoryForTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return 'nonRole';
  if (isWeightedBodyNoiseTag(tag)) return 'nonRole';
  if (/^artist[:\s]/.test(normalized) || normalized.startsWith('@')) {
    return 'nonRole';
  }
  if (hasTornReplacementEvidence(normalized)) {
    if (/\b(pantyhose|stockings?|thighhighs?|socks?|legwear|panties|underwear|bikini bottoms?|pants|shorts|skirt)\b/.test(normalized)) {
      return 'lowerClothing';
    }
    if (/\b(bra|bodysuit|leotard|swimsuit|bikini|dress|shirt|blouse|halter top|top|jacket|coat|suit)\b/.test(normalized)) {
      return 'upperClothing';
    }
  }
  if (isHardNonRoleTerm(normalized)) {
    return 'nonRole';
  }
  if (isActualTowelForStageKey(normalized)) return 'upperClothing';
  if (/\b(no bra)\b/.test(normalized)) return 'upperClothing';
  if (/\b(no panties|no underwear|no overall|no overalls)\b/.test(normalized)) {
    return 'lowerClothing';
  }
  if (genericIdentityMap[normalized] || isConcreteCharacterTag(tag)) {
    return 'identity';
  }
  if (/\b(paw gloves|gloves?)\b/.test(normalized)) return 'upperClothing';
  if (/\b(tail|paw|hooves?)\b/.test(normalized)) return 'lowerBody';
  if (
    /\b(fundoshi|loincloth|male\b.*\bswimsuit|shoes?|boots?|sneakers?|socks?|thighhigs|thighhighs?|pantyhose|stockings?|sandals?|heels?|pants|shorts|skirt|miniskirt|panties|underwear|briefs|trousers|leggings|garter|legwear|buruma|bikini bottoms?|bikini bottom only|side tie bikini bottom|side-tie bikini bottom)\b/.test(
      normalized,
    )
  ) {
    return 'lowerClothing';
  }
  if (
    /\b(shirt|tanktop|blouse|halter top|jacket|hoodie|hood|coat|suit|bunny suit|bunny outfit|bunny girl outfit|dress|uniform|serafuku|school swimsuit|kimono|yukata|bra|bikini|swimsuit|leotard|lingerie|babydoll|baby doll|negligee|chemise|teddy|sleepwear|nightgown|sleeves?|robe|armor|apron|overalls|tank top|crop top|cropped shirt|camisole|vest|cloak|hooded jacket|blazer|sweater)\b/.test(
      normalized,
    )
  ) {
    return 'upperClothing';
  }
  if (
    /\b(hair|eyes?|iris|pupil|ears?|horns?|halo|fang|fangs|skin|face|hat|cap|hair ornament|headdress|headwear|jewelry|earrings?|necklace|choker|collar|ribbon|bow|twintails?|twin tails?|pony ?tail|pigtails?|braids?|bangs?|hairclip|hairband|glasses|crown|bracelet|tattoo|mole|cleavage|collarbone|shoulders?|armpits?|ribs?|chest|breasts?|bust|flat chest|midriff|abs)\b/.test(
      normalized,
    )
  ) {
    return 'upperBody';
  }
  if (
    /\b(thighs?|thick thighs?|bare legs?|legs?|navel|stomach|hips?|waist|barefoot|toes?|thighcut)\b/.test(
      normalized,
    )
  ) {
    return 'lowerBody';
  }
  if (
    /\b(shoes?|boots?|sneakers?|socks?|thighhigs|thighhighs?|pantyhose|stockings?|sandals?|heels?|pants|shorts|skirt|miniskirt|panties|underwear|briefs|trousers|leggings|garter|legwear|buruma|bikini bottoms?|bikini bottom only|side tie bikini bottom|side-tie bikini bottom)\b/.test(
      normalized,
    )
  ) {
    return 'lowerClothing';
  }
  if (
    /\b(shirt|tanktop|blouse|halter top|jacket|hoodie|hood|coat|suit|bunny suit|bunny outfit|bunny girl outfit|dress|uniform|serafuku|school swimsuit|kimono|yukata|bra|bikini|swimsuit|leotard|lingerie|babydoll|baby doll|negligee|chemise|teddy|sleepwear|nightgown|sleeves?|robe|armor|apron|overalls|tank top|crop top|cropped shirt|camisole|vest|cloak|hooded jacket|blazer|sweater)\b/.test(
      normalized,
    )
  ) {
    return 'upperClothing';
  }
  if (
    /\b(bathroom|bath|bathtub|shower|onsen|hot spring|workshop|factory|garage|mechanic|school|classroom|train|subway|station|street|city|bedroom|bed|indoors|outdoors)\b/.test(
      normalized,
    )
  ) {
    return 'context';
  }
  if (
    /\b(nude|naked|topless|bottomless|no clothes|undressing|clothed|quality|masterpiece|aesthetic|simple illustration|collaboration|solo|multiple views|text|looking|sitting|standing|lying|kneeling|closed eyes|open mouth|blush|crying|pain|sex|cum|orgy|fingering|petting|penetration|spread legs|breasts|ass|pussy|penis|nipples|areola|pubic|vaginal|anal|censored|mosaic)\b/.test(
      normalized,
    )
  ) {
    return 'nonRole';
  }
  const classified = classificationCategoryForTag(tag);
  if (classified === 'upperBody') return 'upperBody';
  if (classified === 'lowerBody') return 'lowerBody';
  if (classified === 'upperClothing') return 'upperClothing';
  if (classified === 'lowerClothing') return 'lowerClothing';
  if (classified === 'scene') return 'context';
  if (
    ['artist', 'quality', 'action', 'camera', 'other'].includes(classified)
  ) {
    return 'nonRole';
  }
  return 'nonRole';
}

function isWeightedBodyNoiseTag(tag) {
  const raw = stringValue(tag).trim();
  if (!raw) return false;
  if (!/^\(+.*\)+$/.test(raw)) return false;
  const normalized = normalizedTagKey(
    raw
      .replace(/[()]/g, ' ')
      .replace(/:/g, ' ')
      .replace(/\s+/g, ' ')
      .trim(),
  );
  return /^(?:4 toes|feet|foot|barefoot|shiny skin)(?:\s+[\d.]+)*$/.test(
    normalized,
  );
}

function isHardNonRoleTerm(normalized) {
  if (
    /\b(dull eyes?|wide eyes?|vacant eyes?|dead eyes?|averting eyes?|shaded face|face turned sideways|showing flushed face|eyes? rolled back|ahegao|unfocused|dutch angle|dynamic angle|pov hands?|unworn|liquid on skin|face smushed|squished face|legs? wrapped around waist|relaxed shoulder movement|navel|thighs?|exposed breasts?|nude breasts?|exposed nipples?|deep cleavage (?:fully exposed|spilling out)|bare shoulders and thighs|exposing hips|heaving chest|flushed heaving chest|deeply flushed heaving chest)\b/.test(
      normalized,
    )
  ) {
    return true;
  }
  if (
    /\b(leg up|legs? lift|legs? apart|open legs?|one leg up|view between legs|hugging own legs|squeezing thighs|squeezing breasts|breast squeeze|breast grobbed|breast grabbed|breast grab|grab breast|grapping .*breast|grabbing breast|groping .*breasts?|breasts? fully bouncing|breasts? bouncing|bouncing breast|jiggling|handling .*legs?|adjusting hair|fixing hair|brushing hair|combing hair|touching hair|messy hair|narrowed eyes?|half-closed eyes?|hair grab|grab .*hair|grabbing .*hair|pulling .*hair|face grab|grab .*face|leg grab|legs? grab|grab .*legs?|thigh grab|thighs? grab|firm grip on thighs|hands? on another|hand on another|arms? on another|pov arms?|large hands?|transparent body|bare arms?|onee shota|grab panties|panties grab|grab another|grabbing another|outstretched legs|legs down|legs limp|legs fully extended|pushing girl s legs|pushing hips up|forcing legs open|below waist not visible|waist motion blur|spraed legs|streching legs|bend her legs|bending her legs|crossed legs|legs chain restrained|legs? lock|leg lock|split legs|knees? to chest|knee to chest|breast touch|rapid hip movement|hip movement|legs wide open|wide open legs|dangling legs|legs dangling|spreading legs|spreading another|spreads? .*legs|bound legs|tentacle bind|tentacle between breasts?|motion blur|blurred hair movement|watching|bikini aside|swimsuit aside|leotard aside|bra aside|shirt aside|skirt aside|skirt lift|clothes aside|panties aside|panties and bra at floor|dress lift|removing shoes|covering .*mouth|finger on pussy|stethoscope on pussy|penis insert|insert .*mouth|one ripping .*halter top|ripping .*top|tearing .*clothes|yanking down .*dress|tearing .*shreds?|commanding battle face|realistic hair and skin|lifting person)\b/.test(
      normalized,
    )
  ) {
    return true;
  }
  if (
    new Set([
      'bow',
      'teeth',
      'head back',
      'head out frame',
      'head down',
      'head tilt',
      'head tilt back',
      'head tilted back',
      'head tilted aside',
      'head turning back',
      'head on pillow',
      'face down',
      'raised head',
      'rolling eyes',
      'eyes rolled back',
      'covered eyes',
      'covered eyes',
      'detailed face',
      'face focus',
      'focus face',
      'face to face',
      'face close to man pants bulge',
      'face on ground',
      'face pressed into bed',
      'face pressed into pillow',
      'face pressed against floor',
      'face pressed against stone floor',
      'frightened eyes',
      'hair cover face',
      'heart in eye',
      'heart in eyes',
      'sharp eyes',
      'smile',
      'male smile',
      'female smile',
      'angry face',
      'facial',
      'wet hair',
      'wet panties',
      'wet panty',
      'semen on skin',
      'sweaty skin',
      'sweaty body',
      'steaming body',
      'closed eye',
      'hair censor',
      'troll face',
      'bulging eyes',
      'shaded face',
      'deep flushed face',
      'flushed face',
      'face flushed',
      'face flushed deep red',
      'pale face',
      'magical girl pale face',
      'extremely red face',
      'fear face',
      'despairing face',
      'distorted face',
      'very distorted face',
      'shocked face',
      'partially shaded face',
      'dull eyes',
      'girl shaded face and dull eyes',
      'girl s shaded face',
      "girl's shaded face",
      'face turned sideways showing flushed face',
      'face up',
      'face to the ground',
      'face not visible',
      'no face',
      'no face visible',
      'no face details',
      "no man's face in screen",
      'male teeth',
      'white teeth',
      'messy lower body',
      'thighhold',
      'elegant posture',
      'on stomach',
      'legs together',
      'legs up',
      'stomach bulge',
      'breast press',
      'bouncing breasts',
      'breasts squeezed together',
      'plantar flexion and legs up',
      'slapping mark on stomach',
      'tattoo machine laser',
      'face down on chest',
      'only face',
      'motion lines',
      'detailed eyes',
      'smooth skin',
      'frightened face',
      'Frightened face',
      'face to crotch',
      'nude male arm',
      "nude male's arm",
      'nude male s arm',
      'hand wedgie girl panties up',
      'girl panties up',
      'dress tug',
      'skirt flip',
      'skirt pull',
      'adjusting clothes',
      'forced exposure',
      'pussy cutout',
      'breasts out',
      'breast out',
      'bikini top pull',
      'hands on bikini top',
      'undressing another',
      'clitoral hood',
      'face in crotch',
      'chair',
      'cover mouth with a towel',
      'covering mouth with a towel',
      'holding towel',
      'shower place',
      'bathroom place',
      'turn face away',
      'turning head',
      'lean face forward',
      'lifted skirt',
      'lower her head in shame',
      'paw pose',
      'shake head',
      'shake your head',
      'white panties pulled aside',
      'girlfriend kari',
      'koi koisan',
      'no humans',
      'recruitment',
      'recruitment blue archive',
      'energy drink',
      'dutch angle',
      'unworn clothes',
      'unworn bra',
      'unworn shirt',
      'unworn skirt',
      'unworn pants',
      'on the table',
      'energy drink and condom boxe on the table center',
      'energy drink and condom box on the table center',
    ]).has(normalized)
  ) {
    return true;
  }
  if (
    /\b(pulling down legwear|clenching teeth|clenched teeth|gritting teeth|coverd eyes|covered eyes|closed eye|eyes wide open|one eye closed|dashed eyes|uneven eyes|glistening eyes|bulging eyes|heart in eyes?|rape eyes?|no highlights|troll face|hair censor|face pressed|face in pillow|face on bed|face in crotch|face to crotch|pressed into|pressed against|pressing against|tears streaming down face|tearing up|shading eyes|bra off|bra down|hand bra|water splash on face|face next to man pants bulge|close up|close-up|from side|side face|front face view|monitor on wall|on floor|on the floor|on sofa|shirt pulled aside|pulled aside|taking off|undressing|undressing another|vibrator|vibrators? on legs|licking|sucking|touching|caress(?:ing)?|angry|despair|scared|surprised face|tired eyes|clitoral hood|holding towel|cover mouth with a towel|covering mouth with a towel|male'?s? arm|girl panties|girl'?s? navel|girl navel|wedgie|partially undressed|torn clothes|forced exposure|pussy cutout|bikini top pull|hands on bikini top|holding .*pant(?:y|ies)|holding .*bra|holding .*skirt|holding raised leg|pant(?:y|ies) in .*hand|look(?:ing)? at pant(?:y|ies)|cum on pant(?:y|ies)|tearing .*bra|tearing .*skirt|tearing other(?:'?s| s) pant(?:y|ies)|tearing clothes with bra|panty pull|pants on head|unbuttoning other(?:'?s| s) shirt|removing other(?:'?s| s) bra|removing other(?:'?s| s) skirt|removing other(?:'?s| s) pant(?:y|ies)|spreading other'?s? legs|slap another face|slapped to the side|hand under chin|opening legs|shaking tail|left leg over head|leg over head|heel up|girl inside stomach|inside stomach|squashed? .*stomach|stomping on .*stomach|over girl|thick legs over girl|male legs over girl|boy'?s? leg|watching|watching .*|behind|behind .*|on top of|fondling|gripping breast|pressing against|bow her head|dot eyes|no eyes|hide eyes|eyes in shadow|evil eyes|wild eyes|bondage breasts|m legs)\b/.test(
      normalized,
    )
  ) {
    return true;
  }
  return /\b(hand|hands|arm|arms|finger|fingering|petting|grab|grabbing|another s|another's|other'?s?|hold|holding|pull|pulled|pulling|push|tug|covering|spread|sitting|standing|lying|kneeling|looking|watching|behind|lifting|lifted|shake|shaking|tilted|closed eyes|open mouth|blush|crying|tear|tears|pain|head back|head down|head tilt|head out of frame|out of frame|folded knees|knees?|chain leash|leash|skirt flip|skirt lift|skirt pull|shirt lift|dress tug|panties aside|clothes lift|open towel|heavy breathing|moaning|orgasm|weak|panic|trembling|dazed|empty eyes|naughty face|wet|sweaty|sweat|stained|torn|ripped|damaged|sex|cum|semen|saliva|orgy|penetration|missionary|doggystyle|position|facial|smile|ass|pussy|penis|nipples?|areola|pubic|vaginal|anal|censored|mosaic|crime scene|corpse|dead|kidnapping|chloroform|strangle|punishment|body writing|tally|spade tattoo|race fetishism symbol|on stomach|legs together|legs up|plantar flexion|stomach bulge|breast press|bouncing breasts|breasts? out|squeezed together|slapping mark|hard nipple|hide nipple|tattoo machine|condom box|energy drink|mart text|face flushed deep red|partially shaded face|very distorted face|magical girl pale face|face to the ground|face not visible)\b/.test(
    normalized,
  );
}

function isConcreteCharacterTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized || genericIdentityMap[normalized]) return false;
  const parsed = parseCharacterTag(tag);
  if (!parsed.canonicalName || isPseudoCharacterActionTag(parsed.canonicalName)) {
    return false;
  }
  if (isHardNonRoleTerm(normalized)) return false;
  if (isPseudoCharacterActionTag(normalized)) return false;
  if (isKnownFranchiseCharacterTag(tag, normalized)) return true;
  if (isVariantNamedCharacterTag(tag)) return true;
  if (categoryForTagWithoutCharacter(tag) !== 'unknown') return false;
  const classified = classificationCategoryForTag(tag);
  if (classified === 'character' && !/\b(fox|cat|dog|animal) girl\b/.test(normalized)) {
    return true;
  }
  if (classified && classified !== 'character') {
    return false;
  }
  return /[_\s]*\([^)]{3,}\)/.test(tag) && !/^artist[:\s]/i.test(tag);
}

function isVariantNamedCharacterTag(tag) {
  const text = stringValue(tag).trim();
  if (!/[_\s]*\([^)]{3,}\)/.test(text) || /^artist[:\s]/i.test(text)) {
    return false;
  }
  const parsed = parseCharacterTag(text);
  const canonical = normalizedTagKey(parsed.canonicalName);
  if (!canonical || isPseudoCharacterActionTag(canonical)) return false;
  if (!(parsed.variantTags ?? []).some(isVariantOnlyCharacterGroup)) return false;
  if (knownFallbackRoleTranslation(canonical)) return true;
  return /^[a-z]+(?:\s+[a-z]+){1,3}$/.test(canonical);
}

function isPseudoCharacterActionTag(normalized) {
  const parsed = parseCharacterTag(normalized);
  const name = normalizedTagKey(parsed.canonicalName || normalized);
  return /\b(watching|looking|holding|grabbing|pressing|fondling|slapping|slap|kneeling|standing|sitting|lying|on top of|against|under|over|inside|bathroom|shower|recruitment|ui|screen|source|vision|object|dutch angle|dynamic angle|pov hands?)\b/.test(
    name,
  );
}

function isKnownFranchiseCharacterTag(tag, normalized) {
  const raw = stringValue(tag);
  if (!/[_\s]*\([^)]{3,}\)/.test(raw) || /^artist[:\s]/i.test(raw)) {
    return false;
  }
  return /\b(fate|princess connect|blue archive|azur lane|genshin impact|honkai|star rail|arknights|granblue fantasy|zenless zone zero|re zero|date a live|hololive|idolmaster|girls frontline|touhou|kancolle|umamusume|flower knight girl|black survival)\b/.test(
    normalized,
  );
}

function categoryForTagWithoutCharacter(tag) {
  const normalized = normalizedTagKey(tag);
  if (/\b(dutch angle|dynamic angle|pov hands?)\b/.test(normalized)) {
    return 'knownNonCharacter';
  }
  if (
    /\b(hair|eyes?|iris|pupils?|ears?|horns?|halo|fangs?|face|skin|tail|hat|cap|hood|headdress|headwear|shirt|jacket|skirt|shorts|pants|panties|shoes?|boots?|socks?|nude|sex|cum|artist|quality|solo|hand|hands|frame|flip|lift|open clothes|shower|bathroom|bath|place|locker room|bedroom|school|classroom|chair|vision|object|faceless male|twintails?|twin tails?|pony ?tail|pigtails?|braids?|bangs?|hairclip|hairband|ribbon|bow|glasses|crown|bracelet|tattoo|mole|cleavage|collarbone|shoulders?|armpits?|ribs?|chest|breasts?|bust|midriff|abs|navel|stomach|thighs?|legs?|feet|foot|toes?|uniform|bikini|swimsuit|dress|kimono|yukata|gloves?)\b/.test(
      normalized,
    )
  ) {
    return 'knownNonCharacter';
  }
  return 'unknown';
}

function parseCharacterTag(tag) {
  const text = stringValue(tag).trim();
  if (!text) {
    return { canonicalName: '', franchise: '', variantTags: [] };
  }
  const normalized = text.replace(/_/g, ' ');
  const groups = [...normalized.matchAll(/\(([^)]*)\)/g)]
    .map((match) => match[1].trim())
    .filter(Boolean);
  const canonicalName = canonicalCharacterName(
    normalized.replace(/\([^)]*\)/g, ' ').trim(),
  );
  const lastGroup = groups.length > 0 ? groups[groups.length - 1] : '';
  const franchise = isVariantOnlyCharacterGroup(lastGroup)
    ? ''
    : canonicalFranchiseName(lastGroup);
  const variantTags = franchise ? groups.slice(0, -1) : groups;
  return { canonicalName, franchise, variantTags };
}

function canonicalCharacterName(name) {
  const normalized = normalizedTagKey(name);
  const aliases = {
    ffirefly: 'firefly',
  };
  return aliases[normalized] ?? name.replace(/\bffirefly\b/gi, 'firefly');
}

function canonicalFranchiseName(name) {
  const normalized = normalizedTagKey(name);
  const aliases = {
    'eternal return': 'black survival',
    'glanblue fantasy': 'granblue fantasy',
    'princess connect': 'princess connect!',
    'princess connect re dive': 'princess connect!',
  };
  return aliases[normalized] ?? name;
}

function isVariantOnlyCharacterGroup(name) {
  const normalized = normalizedTagKey(name);
  if (!normalized) return false;
  return /\b(costume|outfit|mechanic|summer|new year|ceremonial|bunny girl|idol|dress|swimsuit|halloween|school uniform|maid|cheerleader|first ascension|second ascension|third ascension|1st|2nd|3rd)\b/.test(
    normalized,
  );
}

function fieldReasons(fields) {
  return {
    identity: fields.identity
      ? 'Identity terms appear in the assigned role slot evidence.'
      : 'No stable identity term was present in this role slot evidence.',
    upper_body: fields.upperBody
      ? 'Upper body/accessory terms are sourced from assigned role frames.'
      : 'No stable upper-body role evidence was present.',
    lower_body: fields.lowerBody
      ? 'Lower body/accessory terms are sourced from assigned role frames.'
      : 'No stable lower-body role evidence was present.',
    upper_clothing: fields.upperClothing
      ? 'Upper clothing terms are sourced from assigned role frames.'
      : 'No stable upper-clothing evidence was present.',
    lower_clothing: fields.lowerClothing
      ? 'Lower clothing terms are sourced from assigned role frames.'
      : 'No stable lower-clothing evidence was present.',
  };
}

function missingFields(fields) {
  const missing = [];
  if (!fields.identity) missing.push('missing_identity');
  if (!fields.upperBody) missing.push('missing_upper_body');
  if (!fields.lowerBody) missing.push('missing_lower_body');
  if (!fields.upperClothing) missing.push('missing_upper_clothing');
  if (!fields.lowerClothing) missing.push('missing_lower_clothing');
  return missing;
}

function artistChainsForFrames(frames) {
  const counts = new Map();
  for (const frame of frames) {
    for (const tag of parseTags(frame.parsed?.baseCaption)) {
      if (/^artist[:\s]/i.test(tag)) addTerm(counts, tag);
    }
  }
  return topTerms(counts, 2, 20).map((term, index) => ({
    label: `画师串 ${index + 1}`,
    terms: [term],
    frame_indexes: [],
    confidence: 0.72,
    evidence_terms: [term],
  }));
}

function strongFilterKeywordsForFrames(frames) {
  const counts = new Map();
  for (const frame of frames) {
    const text = [
      frame.parsed?.baseCaption,
      frame.parsed?.negativeBase,
      ...(Array.isArray(frame.parsed?.charCaptions)
        ? frame.parsed.charCaptions
        : []),
    ].join(', ');
    for (const tag of parseTags(text)) {
      if (/\b(censored|mosaic|bar censoring|text|watermark)\b/i.test(tag)) {
        addTerm(counts, tag);
      }
    }
  }
  return topTerms(counts, 2, 20).map((term, index) => ({
    id: `strong-filter-${index + 1}`,
    term,
    frame_indexes: [],
    reason: 'Strong filter/censor keyword found in source evidence.',
  }));
}

function parseTags(text) {
  return stripNegativeWeightedGroups(stringValue(text).replace(/\r?\n/g, ','))
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/::+/g, ',')
    .replace(/[\uFF0C\u3001\uFF1B]/g, ',')
    .replace(/[，、；]/g, ',')
    .replace(/[，、；;|]+/g, ',')
    .split(',')
    .map(cleanTag)
    .filter(Boolean);
}

function stripNegativeWeightedGroups(text) {
  return stringValue(text).replace(/-\d+(?:\.\d+)?\s*::[\s\S]*?::/g, ',');
}

function cleanTag(value) {
  let text = stringValue(value).trim();
  if (!text) return '';
  text = text.replace(/^["']|["']$/g, '').trim();
  if (/^-\d+(?:\.\d+)?\s*::\s*/.test(text)) return '';
  let changed = true;
  while (changed) {
    const leadingWeight = text.match(/^([+-]?\d+(?:\.\d+)?)\s*::\s*/);
    if (leadingWeight && Number(leadingWeight[1]) <= 0) return '';
    const next = text.replace(/^[+]?\d+(?:\.\d+)?\s*::\s*/g, '').trim();
    changed = next !== text;
    text = next;
  }
  text = text.replace(/::+$/g, '').replace(/^:+|:+$/g, '').trim();
  text = text
    .replace(
      /^((?:1\s*)?(?:girl|girls|female|woman|loli|boy|boys|male|man|men))\s+[+-]?\d+(?:\.\d+)?$/i,
      '$1',
    )
    .trim();
  text = text.replace(/^(?:and|with)\s+/i, '').trim();
  const weighted = text.match(/^\((.*):([+-]?\d+(?:\.\d+)?)\)$/);
  if (weighted) {
    if (Number(weighted[2]) <= 0) return '';
    text = weighted[1].trim();
  }
  let unwrapped = true;
  while (unwrapped) {
    const next = text.match(/^\(([^()]+)\)$/);
    if (!next) {
      unwrapped = false;
    } else {
      text = next[1].trim();
    }
  }
  text = text.replace(/\s+/g, ' ').trim();
  if (!text || text === '-' || text === '::') return '';
  return text;
}

function translate(term) {
  const normalized = normalizedTagKey(term);
  if (knownTermTranslations[normalized]) {
    return { text: knownTermTranslations[normalized], fallback: false };
  }
  const keys = translationKeys(term);
  for (const key of keys) {
    const entry = translationCache[key];
    if (entry?.translation && String(entry.translation).trim()) {
      const text = String(entry.translation).trim();
      if (hasChinese(text) || hasChinese(term)) {
        return { text, fallback: false };
      }
    }
  }
  if (genericIdentityMap[normalized]) {
    return { text: genericIdentityMap[normalized].zh, fallback: false };
  }
  if (/[\u4e00-\u9fff]/.test(term)) {
    return { text: term, fallback: false };
  }
  return { text: fallbackDisplay(term), fallback: true };
}

function translationKeys(term) {
  const raw = stringValue(term).trim();
  const lower = raw.toLowerCase();
  const spaced = raw.replace(/_/g, ' ');
  return unique([
    `${raw}_en2zh`,
    `${lower}_en2zh`,
    `${spaced}_en2zh`,
    `${spaced.toLowerCase()}_en2zh`,
    `${normalizedTagKey(raw)}_en2zh`,
  ]);
}

function fallbackDisplay(term) {
  const parsed = parseCharacterTag(term);
  const normalized = normalizedTagKey(term);
  const canonical = normalizedTagKey(parsed.canonicalName || term);
  const franchise = franchiseDisplayName(parsed.franchise || normalized);
  const exact =
    knownFallbackRoleTranslation(normalized) ??
    knownFallbackRoleTranslation(
      franchise ? `${canonical} ${normalizedTagKey(parsed.franchise)}` : canonical,
    ) ??
    knownFallbackRoleTranslation(canonical);
  if (exact) return exact;

  const generic = genericFallbackRoleDisplay(normalized || canonical);
  if (generic) return franchise ? `${generic}（${franchise}）` : generic;
  if (franchise) return `未命名人物（${franchise}）`;
  return '未命名人物';
}

function knownFallbackRoleTranslation(normalized) {
  const key = normalizedTagKey(normalized);
  const overrides = {
    'kariza princess connect': '\u5361\u5229\u624e\uff08\u516c\u4e3b\u8fde\u7ed3\uff09',
    'nea princess connect': '\u6d85\u5a05\uff08\u516c\u4e3b\u8fde\u7ed3\uff09',
    'nea summer princess connect':
      '\u6d85\u5a05\uff08\u590f\u65e5\uff09\uff08\u516c\u4e3b\u8fde\u7ed3\uff09',
  };
  if (overrides[key]) return overrides[key];
  const map = {
    'tsumugi halloween princess connect': '纺希（万圣节）（公主连结）',
    'recruitment blue archive': '招募画面（碧蓝档案）',
    'doodle sensei blue archive': '涂鸦老师（碧蓝档案）',
    'doddle sensei blue archive': '涂鸦老师（碧蓝档案）',
    'yeshunguang zenless zone zero': '叶瞬光（绝区零）',
    'saika magoichi fate/grand order': '杂贺孙一（Fate/Grand Order）',
    'ethereal zenless zone zero': '以骸（绝区零）',
    'artoria caster fgo second ascension 18 years old adult version':
      '阿尔托莉雅·Caster（二阶段成人版）（FGO）',
    'clear princess connect': '克莉亚（公主连结）',
    'luna shadowverse': '露娜（影之诗）',
    'enterprise azur lane': '企业（碧蓝航线）',
    'st. louis luxurious wheels azur lane': '圣路易斯（Luxury Handle）（碧蓝航线）',
    'st louis luxurious wheels azur lane': '圣路易斯（Luxury Handle）（碧蓝航线）',
    'commander azur lane': '指挥官（碧蓝航线）',
    'firefly honkai star rail': '流萤（崩坏：星穹铁道）',
    'honkai star rail': '星穹铁道人物',
    'hina dress blue archive': '日奈（礼服）（碧蓝档案）',
    'hina swimsuit blue archive': '日奈（泳装）（碧蓝档案）',
    'chinatsu blue archive': '千夏（碧蓝档案）',
    'bremerton azur lane': '布莱默顿（碧蓝航线）',
    'taihou azur lane': '大凤（碧蓝航线）',
    'sheffy princess connect': '雪菲（公主连结）',
    'trianne honkai star rail': '缇安妮（崩坏：星穹铁道）',
    'trinnon honkai star rail': '缇农（崩坏：星穹铁道）',
    'florina fire emblem': '芙罗莉娜（火焰之纹章）',
    'hornet rance': '赫妮特（兰斯）',
    'hu tao genshin impact': '胡桃（原神）',
    'zhongli genshin impact': '钟离（原神）',
    'paimon genshin impact': '派蒙（原神）',
    'ganyu genshin impact': '甘雨（原神）',
    'ameth princess connect': '阿梅斯（公主连结）',
    'kokkoro princess connect': '可可萝（公主连结）',
    'eriko summer princess connect': '惠理子（夏日）（公主连结）',
    'shizuru summer princess connect': '静流（夏日）（公主连结）',
    'shizuru princess connect': '静流（公主连结）',
    'producer idolmaster': '制作人（偶像大师）',
    'miyako swimsuit blue archive': '宫子（泳装）（碧蓝档案）',
    'neneka princess connect': '似似花（公主连结）',
    'darjeeling girls und panzer': '大吉岭（少女与战车）',
    'gran granblue fantasy': '格兰（碧蓝幻想）',
    'yuuki princess connect': '佑树（公主连结）',
    'misora summer princess connect': '美空（夏日）（公主连结）',
    'chiara eternal return': '琪娅拉（永恒轮回）',
    'watching chiara': '琪娅拉（观战）',
    'makoto blue archive': '真琴（碧蓝档案）',
    'hatsune summer princess connect': '初音（夏日）（公主连结）',
    'sensei blue archive the animation': '老师（碧蓝档案动画）',
    'citlali genshin impact': '茜特菈莉（原神）',
    'gawr gura': '噶呜·古拉',
    'la darknesss': '拉普拉斯·达克尼斯',
    'la+ darknesss': '拉普拉斯·达克尼斯',
    'hoshikawa sara': '星川莎拉',
    'koyuki blue archive': '小雪（碧蓝档案）',
    'hoshimachi suisei sailor': '星街彗星（水手服）',
    'columbina genshin impact': '哥伦比娅（原神）',
    'castorice honkai star rail': '遐蝶（崩坏：星穹铁道）',
    'kanroji mitsuri': '甘露寺蜜璃',
    'rosa pokemon': '鸣依（宝可梦）',
    'baobhan sith swimsuit pretender first ascension fate':
      '妖精骑士崔斯坦（泳装一阶段）（Fate）',
    'baobhan sith fate': '妖精骑士崔斯坦（Fate）',
    'eblana arknights': '爱布拉娜（明日方舟）',
    'reed arknights': '苇草（明日方舟）',
    'inugami korone hololive': '戌神沁音（Hololive）',
    'cartethyia wuthering waves': '卡提希娅（鸣潮）',
    'kirara genshin impact': '绮良良（原神）',
    'alisa mikhailovna kujou tokidoki bosotto roshia go de dereru tonari no alya san':
      '艾莉莎·米哈伊洛夫纳·九条',
    'seia blue archive': '圣娅（碧蓝档案）',
    'vivian banshee zenless zone zero': '薇薇安（绝区零）',
    'ruan mei honkai star rail': '阮梅（崩坏：星穹铁道）',
    'houshou marine hololive': '宝钟玛琳（Hololive）',
    'sakamata chloe': '沙花叉克萝耶',
    'robin honkai star rail': '知更鸟（崩坏：星穹铁道）',
    'arima kana oshi no ko': '有马加奈（我推的孩子）',
    'artoria pendragon fate': '阿尔托莉雅·潘德拉贡（Fate）',
    'professor niyaniya blue archive': '尼娅尼娅教授（碧蓝档案）',
    'the herta honkai star rail': '大黑塔（崩坏：星穹铁道）',
    'elysia herrscher of human ego honkai impact': '爱莉希雅（人之律者）（崩坏3）',
    'eris greyrat': '艾莉丝·格雷拉特',
    'roxy migurdia': '洛琪希·米格路迪亚',
    'sylphiette mushoku tensei': '希露菲叶特（无职转生）',
    'ellen joe': '艾莲·乔',
    'hoshino swimsuit blue archive': '星野（泳装）（碧蓝档案）',
    'ui blue archive': '忧（碧蓝档案）',
    'shirakami fubuki hololive': '白上吹雪（Hololive）',
    'suzuran spring praise arknights': '铃兰（春颂）（明日方舟）',
    'warmy arknights': '温米（明日方舟）',
    'amiya arknights': '阿米娅（明日方舟）',
    'mudrock arknights': '泥岩（明日方舟）',
    'black swan honkai star rail': '黑天鹅（崩坏：星穹铁道）',
    'fu xuan honkai star rail': '符玄（崩坏：星穹铁道）',
    'hatsune miku': '初音未来',
    'vikala glanblue fantasy': '维卡拉（碧蓝幻想）',
    'rebellion sword': '叛逆之剑',
    'usada pekora': '兔田佩克拉',
    'aesc rain witch fate': '救世主梣（雨之魔女）（Fate）',
    'illyasviel von einzbern': '伊莉雅丝菲尔·冯·爱因兹贝伦',
    'prisma illya': '魔法少女伊莉雅',
    'aiba asagi anime': '相羽亚衣奈',
    'kasane teto': '重音テト',
    'mash kyrielight demi servant': '玛修·基列莱特（亚从者）',
    'mash kyrielight dangerous beast': '玛修·基列莱特（危险野兽）',
    'mash kyrielight': '玛修·基列莱特',
    'yuni winter princess connect': '优妮（冬日）（公主连结）',
    'raiden shogun': '雷电将军',
    'fire attribute yuel granblue fantasy': '火属性尤艾尔（碧蓝幻想）',
    'sirius azur lane': '天狼星（碧蓝航线）',
    'hart eternal return': '哈特（永恒轮回）',
  };
  return map[key];
}

function genericFallbackRoleDisplay(normalized) {
  const key = normalizedTagKey(normalized);
  if (!key || key === 'role') return '未命名人物';
  if (/\b(?:dark|black)[-\s]*(?:skined|skinned|skinnd)\s+male\b/.test(key)) {
    return '深色皮肤男性';
  }
  if (/\bbald\b|\bbald head\b/.test(key)) return '光头男性';
  if (/\bfaceless\b/.test(key)) return '无脸男性';
  if (/\bsensei\b|\bteacher\b/.test(key)) return '老师';
  if (/\bcommander\b/.test(key)) return '指挥官';
  if (/\bproducer\b/.test(key)) return '制作人';
  if (/\bdoctor\b/.test(key)) return '博士';
  if (/\bprofessor\b/.test(key)) return '教授';
  if (/\b(?:1|2)?girls?\b|\bfemale\b|\bwoman\b/.test(key)) return '女孩';
  if (/\b(?:1)?boys?\b|\bmale\b|\bman\b/.test(key)) return '男性';
  return '';
}

function franchiseDisplayName(value) {
  const key = normalizedTagKey(value);
  if (!key) return '';
  const entries = [
    ['fate/grand order', 'Fate/Grand Order'],
    ['fgo', 'FGO'],
    ['fate', 'Fate'],
    ['princess connect', '公主连结'],
    ['blue archive', '碧蓝档案'],
    ['azur lane', '碧蓝航线'],
    ['genshin impact', '原神'],
    ['honkai star rail', '崩坏：星穹铁道'],
    ['star rail', '崩坏：星穹铁道'],
    ['honkai impact', '崩坏3'],
    ['honkai', '崩坏系列'],
    ['zenless zone zero', '绝区零'],
    ['arknights', '明日方舟'],
    ['granblue fantasy', '碧蓝幻想'],
    ['glanblue fantasy', '碧蓝幻想'],
    ['hololive', 'Hololive'],
    ['idolmaster', '偶像大师'],
    ['shadowverse', '影之诗'],
    ['fire emblem', '火焰之纹章'],
    ['rance', '兰斯'],
    ['girls und panzer', '少女与战车'],
    ['eternal return', '永恒轮回'],
    ['pokemon', '宝可梦'],
    ['wuthering waves', '鸣潮'],
    ['oshi no ko', '我推的孩子'],
    ['mushoku tensei', '无职转生'],
  ];
  const found = entries.find(([needle]) => key.includes(needle));
  return found ? found[1] : '';
}

function hasChinese(value) {
  return /[\u4e00-\u9fff]/.test(stringValue(value));
}

function topStableTerms(counts, frameCount, max) {
  const minCount = frameCount <= 3 ? 1 : Math.max(2, Math.ceil(frameCount * 0.08));
  return topTerms(counts, minCount, max);
}

function topTerms(counts, minCount, max) {
  return [...counts.entries()]
    .filter(([, count]) => count >= minCount)
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
    .map(([term]) => term)
    .slice(0, max);
}

function addTerm(map, term, weight = 1) {
  const clean = cleanTag(term);
  if (!clean) return;
  const key = clean;
  map.set(key, (map.get(key) ?? 0) + weight);
}

function compareGroups(left, right) {
  return (
    Math.min(...left.frames) - Math.min(...right.frames) ||
    left.key.localeCompare(right.key)
  );
}

function frameList(cache) {
  return Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];
}

function isParsedFrame(frame) {
  return stringValue(frame?.parseStatus ?? frame?.parse_status).toLowerCase() ===
    'parsed';
}

function sortedInts(values) {
  return [...values]
    .map(Number)
    .filter((value) => Number.isInteger(value))
    .sort((left, right) => left - right);
}

function unique(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const text = stringValue(value).trim();
    const key = normalizedTagKey(text);
    if (!text || seen.has(key)) continue;
    seen.add(key);
    result.push(text);
  }
  return result;
}

function uniqueId(base, used) {
  let id = base || 'role';
  let index = 2;
  while (used.has(id)) {
    id = `${base}-${index}`;
    index += 1;
  }
  used.add(id);
  return id;
}

function safeId(value) {
  const normalized = normalizedTagKey(value)
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return normalized || 'role';
}

function normalizedTagKey(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}\[\]'":!?，、；;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function classificationCategoryForTag(tag) {
  const raw = cleanTag(tag);
  if (!raw) return undefined;
  const lower = raw.toLowerCase();
  const spaced = lower.replace(/_/g, ' ');
  const normalized = normalizedTagKey(raw);
  const keys = uniqueExact([
    raw,
    lower,
    spaced,
    normalized,
    normalized.replace(/\s+/g, '_'),
    normalized.replace(/\s+/g, '-'),
  ]);
  for (const key of keys) {
    const entry = classificationCache[`positive:${key}`];
    if (entry?.category) return entry.category;
  }
  return undefined;
}

function uniqueExact(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const text = stringValue(value).trim();
    if (!text || seen.has(text)) continue;
    seen.add(text);
    result.push(text);
  }
  return result;
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function loadJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function parseArgs(args) {
  const parsed = {
    cacheDir: undefined,
    outputDir: undefined,
    translationCache: undefined,
    classificationCache: undefined,
    report: undefined,
    limit: undefined,
    nameContains: undefined,
    apply: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    if (key === 'apply') {
      parsed.apply = true;
      continue;
    }
    const value = args[index + 1];
    index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'output-dir') parsed.outputDir = value;
    if (key === 'translation-cache') parsed.translationCache = value;
    if (key === 'classification-cache') parsed.classificationCache = value;
    if (key === 'report') parsed.report = value;
    if (key === 'limit') parsed.limit = Number(value);
    if (key === 'name-contains') parsed.nameContains = value;
  }
  return parsed;
}
