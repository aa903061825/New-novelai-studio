const imagePool = [
  "../../imgs/0001.jpg",
  "../../imgs/0002.jpg",
  "../../imgs/0003.jpg",
  "../../imgs/0004.jpg",
  "../../imgs/0005.jpg",
];

const groupLabels = {
  character: "人物词",
  artist: "画师串词",
  negative: "负面",
};

const categories = [
  {
    id: "all",
    title: "全部",
    note: "所有人物卡与画师串统一浏览。",
    tags: ["人物卡", "画师串"],
  },
  {
    id: "characters",
    title: "人物卡",
    note: "稳定角色词、身体特征、默认服装和来源记录。",
    tags: ["人物卡"],
  },
  {
    id: "artist",
    title: "画师串",
    note: "画风链路、权重串词、风格缓存和可绑定预览。",
    tags: ["画师串"],
  },
];

const assets = [
  {
    id: "legacy-character-sheet-r14",
    type: "角色",
    category: "characters",
    title: "佩佩",
    source: "legacy_artist_workbook",
    status: "待检查",
    summary: "猫耳、猫尾、长发、黑绿短外套；默认服装与星移变体已拆分。",
    previews: [
      preview("default", imagePool[0], "默认服装", "已收纳"),
      preview("variant", imagePool[1], "星移变体", "待复核"),
    ],
    outfits: [
      outfit("default", "默认服装", "已收纳", [
        tag("clothing", "cat_ears", "猫耳", 1),
        tag("clothing", "black_and_green_jacket", "黑绿短外套", 1),
        tag("clothing", "cat_tail", "猫尾", 1),
      ], [preview("pepe-default", imagePool[0], "默认服装预览", "已收纳")]),
      outfit("star-shift", "星移变体", "待复核", [
        tag("clothing", "white_coat", "白色外套", 1),
        tag("clothing", "blue_ribbon", "蓝色缎带", 1),
        tag("clothing", "cat_tail", "猫尾", 1),
      ], [preview("pepe-star-shift", imagePool[1], "星移变体预览", "待复核")]),
    ],
    tags: [
      tag("role", "pepe_(arknights)", "佩佩", 1),
      tag("role", "girl", "女孩", 1),
      tag("role", "cat_girl", "猫娘", 1),
      tag("clothing", "cat_ears", "猫耳", 1),
      tag("clothing", "animal_ear_fluff", "兽耳绒毛", 1),
      tag("clothing", "cat_tail", "猫尾", 1),
      tag("clothing", "open_jacket", "敞开的夹克", 1),
      tag("artist", "ciloranko", "画师：ciloranko", 1),
      tag("artist", "lotus_flower_headdress", "莲花头饰", 1),
      tag("action", "looking_at_viewer", "看向观众", 1),
      tag("scene", "solo_focus", "单人焦点", 1),
      tag("negative", "bad_hands", "坏手", -1),
    ],
  },
  {
    id: "artist-chain-ribbon-03",
    type: "画师串词",
    category: "artist",
    title: "暖色丝带链",
    source: "tag_classification_cache",
    status: "可用",
    summary: "偏暖光、柔线条、透明感皮肤，适合少女角色正面立绘。",
    previews: [
      preview("artist", imagePool[2], "串词预览", "已收纳"),
      preview("artist-b", imagePool[3], "角色套用", "已收纳"),
    ],
    tags: [
      tag("artist", "mignon", "画师：mignon", 1.2),
      tag("artist", "ask_(askzy)", "画师：ask", 0.8),
      tag("artist", "soft_shading", "柔和上色", 1),
      tag("artist", "warm_light", "暖光", 1),
      tag("role", "1girl", "单人女孩", 1),
      tag("action", "smile", "微笑", 1),
      tag("scene", "simple_background", "简洁背景", 1),
      tag("negative", "lowres", "低清", -1),
    ],
  },
  {
    id: "outfit-papyrus-aqua",
    type: "角色",
    category: "characters",
    title: "莎草",
    source: "characters.json",
    status: "可用",
    summary: "人物卡：水绿裙默认服装、白色上衣、手套、细绑带和凉鞋。",
    previews: [
      preview("front", imagePool[4], "正面立绘", "已收纳"),
      preview("test", imagePool[1], "生成测试", "待复核"),
    ],
    outfits: [
      outfit("aqua-default", "默认水绿裙", "已收纳", [
        tag("clothing", "aqua_dress", "水绿连衣裙", 1),
        tag("clothing", "white_shirt", "白色上衣", 1),
        tag("clothing", "sandals", "凉鞋", 1),
      ], [preview("papyrus-aqua", imagePool[4], "水绿裙预览", "已收纳")]),
    ],
    tags: [
      tag("role", "papyrus_(arknights)", "莎草", 1),
      tag("clothing", "aqua_dress", "水绿连衣裙", 1),
      tag("clothing", "white_shirt", "白色上衣", 1),
      tag("clothing", "gloves", "手套", 1),
      tag("clothing", "sandals", "凉鞋", 1),
      tag("artist", "torino_aqua", "画师：torino aqua", 1),
      tag("action", "standing", "站立", 1),
      tag("scene", "full_body", "全身", 1),
    ],
  },
  {
    id: "character-ceobe-r5",
    type: "角色",
    category: "characters",
    title: "刻俄柏",
    source: "legacy_artist_workbook",
    status: "待检查",
    summary: "犬耳、长发、棕色作战服；引用缺少一张默认服装预览。",
    previews: [
      preview("default", imagePool[3], "默认服装", "待复核"),
      emptyPreview("missing", "缺少参考"),
    ],
    outfits: [
      outfit("default", "默认作战服", "待检查", [
        tag("clothing", "brown_outfit", "棕色作战服", 1),
        tag("clothing", "long_hair", "长发", 1),
        tag("clothing", "dog_ears", "犬耳", 1),
      ], [preview("ceobe-default", imagePool[3], "默认作战服预览", "待检查")]),
    ],
    tags: [
      tag("role", "ceobe_(arknights)", "刻俄柏", 1),
      tag("role", "dog_girl", "犬娘", 1),
      tag("clothing", "dog_ears", "犬耳", 1),
      tag("clothing", "long_hair", "长发", 1),
      tag("clothing", "brown_outfit", "棕色服装", 1),
      tag("artist", "ask_(askzy)", "画师：ask", 1),
      tag("action", "dynamic_pose", "动态姿势", 1),
    ],
  },
  {
    id: "artist-chain-noir-12",
    type: "画师串词",
    category: "artist",
    title: "冷调夜景链",
    source: "artist_chains.json",
    status: "可用",
    summary: "夜景、冷色边缘光、胶片颗粒，适合剧本重绘镜头。",
    previews: [
      preview("noir", imagePool[2], "夜景测试", "已收纳"),
    ],
    tags: [
      tag("artist", "wlop", "画师：wlop", 0.7),
      tag("artist", "ke-ta", "画师：ke-ta", 0.9),
      tag("artist", "cinematic_lighting", "电影感光照", 1.1),
      tag("scene", "night", "夜晚", 1),
      tag("scene", "rim_light", "边缘光", 1),
      tag("action", "looking_back", "回头看", 1),
      tag("negative", "jpeg_artifacts", "压缩噪点", -1),
    ],
  },
  {
    id: "asset-needs-preview-77",
    type: "角色",
    category: "characters",
    title: "红云",
    source: "legacy_artist_workbook",
    status: "缺预览",
    summary: "红云角色词已导入，预览未生成；适合测试立即生成入口。",
    previews: [emptyPreview("empty", "等待生成")],
    outfits: [
      outfit("default", "默认围巾服", "缺预览", [
        tag("clothing", "scarf", "围巾", 1),
        tag("clothing", "animal_ears", "兽耳", 1),
        tag("clothing", "shorts", "短裤", 1),
      ], [emptyPreview("vermeil-outfit-empty", "等待生成")]),
    ],
    tags: [
      tag("role", "vermeil_(arknights)", "红云", 1),
      tag("role", "fox_girl", "狐娘", 1),
      tag("clothing", "animal_ears", "兽耳", 1),
      tag("clothing", "scarf", "围巾", 1),
      tag("artist", "hou_(rairai)", "画师：hou", 1),
      tag("action", "sitting", "坐姿", 1),
      tag("scene", "white_background", "白背景", 1),
    ],
  },
];

const state = {
  category: "all",
  query: "",
  selectedAssetId: null,
  selectedPreview: 0,
  selectedOutfitId: null,
  density: "gallery",
  editing: null,
  toastTimer: null,
};

function preview(id, src, label, status) {
  return { id, src, label, status, generated: false };
}

function emptyPreview(id, label) {
  return { id, src: null, label, status: "待生成", generated: false };
}

function outfit(id, name, status, tags, previews = []) {
  return { id, name, status, tags, previews };
}

function tag(group, value, zh, weight) {
  return { group, value, zh, weight };
}

function byId(id) {
  return document.getElementById(id);
}

function selectedAsset() {
  return assets.find((asset) => asset.id === state.selectedAssetId) || null;
}

function normalize(value) {
  return value.trim().toLowerCase();
}

function assetMatches(asset) {
  if (state.category !== "all" && asset.category !== state.category) return false;
  if (!state.query) return true;
  const haystack = [
    asset.id,
    asset.type,
    asset.title,
    asset.source,
    asset.status,
    asset.summary,
    ...asset.tags.flatMap((item) => [item.group, item.value, item.zh]),
    ...asset.previews.flatMap((item) => [item.label, item.status]),
  ]
    .join("\n")
    .toLowerCase();
  return haystack.includes(state.query);
}

function promptText(asset) {
  return asset.tags
    .filter((item) => item.group !== "negative")
    .map(formatPromptTag)
    .join(", ");
}

function formatPromptTag(item) {
  if (item.weight === 1) return item.value;
  if (item.weight === -1) return item.value;
  return `${item.weight.toFixed(2).replace(/\.00$/, "")}:: ${item.value} ::`;
}

function render() {
  const visibleAssets = assets.filter(assetMatches);
  renderMetrics();
  renderCategories();
  renderAssets(visibleAssets);
  renderModal();
}

function renderMetrics() {
  byId("metricCharacters").textContent = assets.filter((item) => item.type === "角色").length;
  byId("metricArtists").textContent = assets.filter((item) => item.type === "画师串词").length;
  byId("metricPreviews").textContent = assets.reduce((sum, item) => {
    return sum + item.previews.filter((previewItem) => previewItem.src).length;
  }, 0);
  byId("metricNeeds").textContent = assets.filter((item) => {
    return item.status.includes("待") || item.status.includes("缺");
  }).length;
}

function renderCategories() {
  byId("categoryRail").innerHTML = categories
    .map((category, index) => {
      return `
        <button class="category-card ${state.category === category.id ? "is-active" : ""}"
          type="button" data-category="${category.id}" data-index="${String(index + 1).padStart(2, "0")}">
          <div class="category-title">
            <span>${category.title}</span>
          </div>
        </button>
      `;
    })
    .join("");
}

function renderAssets(visibleAssets) {
  const category = categories.find((item) => item.id === state.category) || categories[0];
  byId("sectionSummary").textContent = `${category.title} / ${category.note}`;
  byId("visibleCount").textContent = `${visibleAssets.length} 个素材`;

  if (visibleAssets.length === 0) {
    byId("assetGrid").innerHTML = `<div class="empty-panel">没有匹配的素材。</div>`;
    return;
  }

  byId("assetGrid").innerHTML = visibleAssets.map(renderAssetCard).join("");
}

function renderAssetCard(asset) {
  const firstPreview = asset.previews.find((item) => item.src);
  return `
    <button class="asset-card" type="button" data-open-asset="${asset.id}">
      <div class="asset-preview">
        ${
          firstPreview
            ? `<img src="${firstPreview.src}" alt="${asset.title} 预览" />`
            : `<div class="preview-stage-empty"><div><strong>暂无预览</strong><span>可立即生成</span></div></div>`
        }
      </div>
      <div class="asset-card-meta">
        <div class="asset-card-badges">
          <span class="type-pill">${asset.type}</span>
          ${asset.status === "可用" ? `<span class="status-pill">可用</span>` : `<span class="status-pill status-warning">${asset.status}</span>`}
        </div>
        <h3>${asset.title}</h3>
        <p>${asset.summary}</p>
      </div>
    </button>
  `;
}

function renderModal() {
  const modal = byId("assetModal");
  const asset = selectedAsset();
  modal.classList.toggle("is-open", Boolean(asset));
  modal.setAttribute("aria-hidden", asset ? "false" : "true");
  if (!asset) return;

  if (state.selectedPreview >= asset.previews.length) {
    state.selectedPreview = Math.max(0, asset.previews.length - 1);
  }

  byId("modalType").textContent = asset.type;
  byId("modalTitle").textContent = asset.title;
  byId("modalSubtitle").textContent = `${asset.id} / ${asset.source}`;
  byId("promptOutput").value = promptText(asset);
  byId("tagSyncStatus").textContent = `${asset.tags.length} 个标签，${countGroups(asset)} 个分组。`;
  renderPreviewPanel(asset);
  renderTagGroups(asset);
}

function countGroups(asset) {
  return new Set(asset.tags.map((item) => item.group)).size;
}

function renderPreviewPanel(asset) {
  const current = asset.previews[state.selectedPreview] || emptyPreview("none", "暂无预览");
  byId("previewStatus").textContent = `${current.label} / ${current.status}`;
  byId("deletePreviewButton").disabled = asset.previews.length === 0;

  byId("previewStage").innerHTML = current.src
    ? `<img src="${current.src}" alt="${asset.title} ${current.label}" />`
    : `<div class="preview-stage-empty"><div><strong>${current.label}</strong><span>${current.status}</span></div></div>`;

  byId("previewRail").innerHTML = asset.previews
    .map((item, index) => {
      return `
        <button class="preview-dot ${index === state.selectedPreview ? "is-active" : ""}"
          type="button" data-preview-index="${index}" aria-label="${item.label}">
          <span>${index + 1}</span>
        </button>
      `;
    })
    .join("");
  byId("previewOutfitSlot").innerHTML = renderOutfitPanel(asset);
}

function renderTagGroups(asset) {
  const groups = tagDisplayGroups(asset).filter((group) => {
    return group.tags.length > 0 || group.id !== "negative";
  });
  byId("tagGroups").innerHTML = groups.map((group) => renderTagGroup(asset, group)).join("");
}

function tagDisplayGroups(asset) {
  return [
    {
      id: "character",
      label: groupLabels.character,
      tags: asset.tags
        .map((item, index) => ({ item, index }))
        .filter((entry) => ["role", "clothing", "action", "scene"].includes(entry.item.group)),
    },
    {
      id: "artist",
      label: groupLabels.artist,
      tags: asset.tags
        .map((item, index) => ({ item, index }))
        .filter((entry) => entry.item.group === "artist"),
    },
    {
      id: "negative",
      label: groupLabels.negative,
      tags: asset.tags
        .map((item, index) => ({ item, index }))
        .filter((entry) => entry.item.group === "negative"),
    },
  ];
}

function renderOutfitPanel(asset) {
  if (asset.type !== "角色" || !asset.outfits?.length) return "";
  const selectedId = state.selectedOutfitId || asset.outfits[0].id;
  const selected = asset.outfits.find((item) => item.id === selectedId) || asset.outfits[0];
  return `
    <section class="outfit-switcher" aria-label="服装">
      <div class="outfit-icon-row">
        ${asset.outfits
          .map((item) => `
            <button class="outfit-icon ${item.id === selected.id ? "is-active" : ""}"
              type="button" data-select-outfit="${item.id}" title="${item.name}">
              ${renderOutfitIcon(item)}
            </button>
          `)
          .join("")}
      </div>
      <div class="outfit-switcher-label">${selected.name} / ${selected.status}</div>
    </section>
  `;
}

function renderOutfitIcon(item) {
  const previewItem = item.previews?.find((previewItem) => previewItem.src);
  if (!previewItem) {
    return `<span class="outfit-icon-empty">装</span>`;
  }
  return `<img src="${previewItem.src}" alt="${item.name} 预览" />`;
}

function renderTagGroup(asset, group) {
  const items = group.tags.map((entry) => ({
    ...entry.item,
    index: entry.index,
    displayGroupId: group.id,
  }));
  const editing = state.editing && state.editing.assetId === asset.id && state.editing.group === group.id;
  return `
    <section class="tag-group" data-tag-group="${group.id}">
      <div class="tag-group-head">
        <strong>${group.label}</strong>
        <span class="mini-tag">${items.length}</span>
      </div>
      <div class="tag-list">
        ${
          items.length === 0
            ? `<span class="mini-tag">空分组</span>`
            : items.map((item) => renderTagChip(item)).join("")
        }
      </div>
      <form class="tag-edit-form" data-edit-form="${group.id}" ${editing ? "" : "hidden"}>
        ${editing ? renderEditFields(asset) : ""}
      </form>
    </section>
  `;
}

function renderTagChip(item) {
  const weight = item.weight !== 1 && item.weight !== -1
    ? `<span class="weight-badge">x${item.weight.toFixed(2).replace(/\.00$/, "")}</span>`
    : "";
  return `
    <span class="tag-chip" data-group="${item.group}">
      <button class="tag-main" type="button" data-edit-tag="${item.index}" data-edit-group="${item.displayGroupId || item.group}">
        <b>${item.value}</b>
        <small>${item.zh || groupLabels[item.group]}</small>
      </button>
      ${weight}
      <button class="tag-delete" type="button" data-delete-tag="${item.index}" aria-label="删除 ${item.value}">×</button>
    </span>
  `;
}

function renderEditFields(asset) {
  const item = asset.tags[state.editing.index];
  if (!item) return "";
  return `
    <input name="value" value="${escapeAttribute(item.value)}" aria-label="tag" />
    <input name="zh" value="${escapeAttribute(item.zh)}" aria-label="中文名" />
    <input name="weight" type="number" step="0.1" value="${item.weight}" aria-label="权重" />
    <select name="group" aria-label="分组">
      ${realTagGroupOptions()
        .map(([group, label]) => `<option value="${group}" ${item.group === group ? "selected" : ""}>${label}</option>`)
        .join("")}
    </select>
    <button class="primary-button" type="submit">保存</button>
  `;
}

function realTagGroupOptions() {
  return [
    ["role", "角色"],
    ["clothing", "服装/身体"],
    ["artist", "画师串词"],
    ["action", "动作"],
    ["scene", "场景/镜头"],
    ["negative", "负面"],
  ];
}

function escapeAttribute(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function openAsset(assetId) {
  state.selectedAssetId = assetId;
  state.selectedPreview = 0;
  state.selectedOutfitId = null;
  state.editing = null;
  render();
}

function closeModal() {
  state.selectedAssetId = null;
  state.editing = null;
  render();
}

function addPreview(asset) {
  const number = asset.previews.length + 1;
  asset.previews.push(emptyPreview(`manual-${Date.now()}`, `新增预览 ${number}`));
  state.selectedPreview = asset.previews.length - 1;
  showToast("已新增一个空预览槽。");
  render();
}

function deletePreview(asset) {
  if (asset.previews.length === 0) return;
  const removed = asset.previews.splice(state.selectedPreview, 1)[0];
  if (asset.previews.length === 0) {
    asset.previews.push(emptyPreview(`empty-${Date.now()}`, "等待生成"));
  }
  state.selectedPreview = Math.max(0, state.selectedPreview - 1);
  showToast(`已删除预览：${removed.label}`);
  render();
}

function generatePreview(asset) {
  const nextIndex = assets.reduce((sum, item) => sum + item.previews.length, 0) % imagePool.length;
  const generated = preview(
    `generated-${Date.now()}`,
    imagePool[nextIndex],
    `即时生成 ${asset.previews.filter((item) => item.generated).length + 1}`,
    "刚生成",
  );
  generated.generated = true;

  const current = asset.previews[state.selectedPreview];
  if (current && !current.src) {
    asset.previews[state.selectedPreview] = generated;
  } else {
    asset.previews.push(generated);
    state.selectedPreview = asset.previews.length - 1;
  }
  asset.status = "可用";
  showToast("已模拟生成预览，并写回当前素材。");
  render();
}

function deleteTag(asset, index) {
  const removed = asset.tags.splice(index, 1)[0];
  if (state.editing?.index === index) state.editing = null;
  showToast(`已删除标签：${removed.value}`);
  render();
}

function startEditTag(asset, index, displayGroupId) {
  const item = asset.tags[index];
  if (!item) return;
  state.editing = { assetId: asset.id, index, group: displayGroupId || item.group };
  render();
}

function saveTagEdit(asset, form) {
  const index = state.editing?.index;
  if (index == null || !asset.tags[index]) return;
  const formData = new FormData(form);
  const value = normalize(String(formData.get("value") || ""));
  if (!value) {
    showToast("tag 不能为空。");
    return;
  }
  const weight = Number(formData.get("weight"));
  asset.tags[index] = {
    group: String(formData.get("group")),
    value,
    zh: String(formData.get("zh") || value).trim(),
    weight: Number.isFinite(weight) ? weight : 1,
  };
  state.editing = null;
  showToast("标签已保存。");
  render();
}

function syncTags(asset) {
  const groups = tagDisplayGroups(asset)
    .map((group) => `${group.label} ${group.tags.length}`)
    .join(" / ");
  showToast(`已同步标签系统：${groups}`);
}

function showToast(message) {
  const toast = byId("toast");
  toast.textContent = message;
  toast.classList.add("is-visible");
  clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => {
    toast.classList.remove("is-visible");
  }, 2100);
}

document.addEventListener("click", (event) => {
  const categoryButton = event.target.closest("[data-category]");
  if (categoryButton) {
    state.category = categoryButton.dataset.category;
    render();
    return;
  }

  const densityButton = event.target.closest("[data-density]");
  if (densityButton) {
    state.density = densityButton.dataset.density;
    document.body.classList.toggle("compact-density", state.density === "compact");
    document.querySelectorAll("[data-density]").forEach((button) => {
      button.classList.toggle("is-active", button === densityButton);
    });
    return;
  }

  const assetButton = event.target.closest("[data-open-asset]");
  if (assetButton) {
    openAsset(assetButton.dataset.openAsset);
    return;
  }

  if (event.target.closest("[data-close-modal]")) {
    closeModal();
    return;
  }

  const previewButton = event.target.closest("[data-preview-index]");
  if (previewButton) {
    state.selectedPreview = Number(previewButton.dataset.previewIndex);
    render();
    return;
  }

  const asset = selectedAsset();
  if (!asset) return;

  const outfitButton = event.target.closest("[data-select-outfit]");
  if (outfitButton) {
    state.selectedOutfitId = outfitButton.dataset.selectOutfit;
    render();
    return;
  }

  if (event.target.closest("#addPreviewButton")) {
    addPreview(asset);
    return;
  }

  if (event.target.closest("#deletePreviewButton")) {
    deletePreview(asset);
    return;
  }

  if (event.target.closest("#generatePreviewButton")) {
    generatePreview(asset);
    return;
  }

  if (event.target.closest("#sendButton")) {
    showToast(`已发送到工作台：${asset.title}`);
    return;
  }

  if (event.target.closest("#copyPromptButton")) {
    navigator.clipboard?.writeText(promptText(asset));
    showToast("已复制 Prompt 串词。");
    return;
  }

  if (event.target.closest("#syncTagsButton")) {
    syncTags(asset);
    return;
  }

  const deleteTagButton = event.target.closest("[data-delete-tag]");
  if (deleteTagButton) {
    deleteTag(asset, Number(deleteTagButton.dataset.deleteTag));
    return;
  }

  const editTagButton = event.target.closest("[data-edit-tag]");
  if (editTagButton) {
    startEditTag(
      asset,
      Number(editTagButton.dataset.editTag),
      editTagButton.dataset.editGroup,
    );
  }
});

document.addEventListener("submit", (event) => {
  const form = event.target.closest("[data-edit-form]");
  if (!form) return;
  event.preventDefault();
  const asset = selectedAsset();
  if (!asset) return;
  saveTagEdit(asset, form);
});

byId("searchInput").addEventListener("input", (event) => {
  state.query = normalize(event.target.value);
  render();
});

byId("newCategoryButton").addEventListener("click", () => {
  const index = categories.length + 1;
  const id = `custom-${index}`;
  categories.push({
    id,
    title: `自定义馆区 ${index}`,
    note: "新增素材可归入这个分类。",
    tags: ["自定义", "收纳"],
  });
  state.category = id;
  showToast(`已创建自定义馆区 ${index}`);
  render();
});

byId("newAssetButton").addEventListener("click", () => {
  const index = assets.length + 1;
  const asset = {
    id: `draft-asset-${index}`,
    type: "角色",
    category: state.category === "all" ? "characters" : state.category,
    title: `新素材 ${index}`,
    source: "prototype",
    status: "缺预览",
    summary: "新建素材草稿。",
    previews: [emptyPreview(`draft-preview-${index}`, "等待生成")],
    tags: [
      tag("role", "1girl", "单人女孩", 1),
      tag("artist", "artist_name", "画师名", 1),
      tag("scene", "simple_background", "简洁背景", 1),
    ],
  };
  assets.unshift(asset);
  state.category = "all";
  openAsset(asset.id);
});

byId("refreshButton").addEventListener("click", () => {
  showToast("已刷新素材索引。");
});

byId("promptOutput").addEventListener("change", (event) => {
  const asset = selectedAsset();
  if (!asset) return;
  const values = event.target.value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  asset.tags = [
    ...asset.tags.filter((item) => item.group === "negative"),
    ...values.map((value) => tag("role", value, value, 1)),
  ];
  showToast("已从 Prompt 文本回写为角色区标签。");
  render();
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && selectedAsset()) {
    closeModal();
  }
});

render();
