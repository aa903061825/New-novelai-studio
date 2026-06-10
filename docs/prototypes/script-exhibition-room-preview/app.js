const categories = [
  {
    id: "all",
    name: "全部馆区",
    description: "所有剧本、原始帧和批量结果统一浏览。",
    tags: ["剧本", "原图", "新图"],
  },
  {
    id: "active",
    name: "连载中",
    description: "仍在持续拆帧、识别角色或等待批量产线回写。",
    tags: ["待生成", "待确认"],
  },
  {
    id: "archived",
    name: "已归档",
    description: "原始剧本和生成结果已完成收纳，可直接回溯。",
    tags: ["可复盘", "知识库"],
  },
  {
    id: "attention",
    name: "需处理",
    description: "缺帧、生成失败、角色证据不足或需要人工确认。",
    tags: ["缺帧", "失败", "证据"],
  },
  {
    id: "school",
    name: "校园馆",
    description: "导入时可手动保存，也可以自动建馆区。",
    tags: ["导入", "自动建类"],
  },
  {
    id: "fantasy",
    name: "奇幻馆",
    description: "适合收纳主角版本、服装状态和世界观变体。",
    tags: ["版本", "服装", "世界观"],
  },
];

const scripts = [
  {
    id: "rain-archive",
    category: "active",
    name: "雨夜档案",
    shelf: "A-02",
    updated: "今天 14:20",
    summary: "雨夜、图书馆、双主角追踪线。原始帧已识别，第二批跑图正在回写。",
    roles: ["女主", "协助者", "临时角色"],
    batches: ["batch-0614-A", "batch-0614-B"],
    incoming: 7,
    attention: 2,
    frames: [
      frame("rain-archive", 1, "original", "original", "ready", 260, "tone-rain", "入口雨幕", "library entrance, wet coat, night rain"),
      frame("rain-archive", 2, "original", "original", "ready", 190, "tone-library", "旧书架前", "old shelves, warm lamp, looking back"),
      frame("rain-archive", 3, "default-run", "generated", "ready", 310, "tone-library", "默认生成：线索书页", "batch B, page clue, close-up"),
      frame("rain-archive", 4, "hero-v1", "generated", "attention", 230, "tone-neon", "主角版 1：色调偏移", "needs color check, neon spill"),
      frame("rain-archive", 5, "original", "original", "ready", 280, "tone-stage", "密谈角落", "two characters, whisper, low light"),
      frame("rain-archive", 6, "rerun", "rerun", "ready", 210, "tone-rain", "单帧重跑：雨窗", "single frame rerun, window rain"),
      frame("rain-archive", 7, "default-run", "generated", "ready", 340, "tone-amber", "默认生成：暖光证据", "batch A, warm desk, evidence"),
      frame("rain-archive", 8, "original", "original", "attention", 180, "tone-snow", "原图缺 metadata", "missing metadata, keep image"),
      frame("rain-archive", 9, "hero-v2", "generated", "ready", 260, "tone-rain", "主角版 2：返回走廊", "batch B, long corridor"),
    ],
  },
  {
    id: "glass-stage",
    category: "archived",
    name: "玻璃舞台",
    shelf: "B-11",
    updated: "昨天 22:08",
    summary: "舞台、镜面、换装段落。所有生成图已完成批次收纳。",
    roles: ["舞台主角", "摄影机"],
    batches: ["batch-0609-C"],
    incoming: 0,
    attention: 0,
    frames: [
      frame("glass-stage", 1, "original", "original", "ready", 250, "tone-stage", "镜面开场", "glass stage, reflection, spotlight"),
      frame("glass-stage", 2, "default-run", "generated", "ready", 320, "tone-stage", "默认生成：主舞台", "batch C, full body, spotlight"),
      frame("glass-stage", 3, "hero-v1", "generated", "ready", 210, "tone-neon", "主角版 1：侧面构图", "side angle, cyan rim light"),
      frame("glass-stage", 4, "rerun", "rerun", "ready", 290, "tone-amber", "单帧重跑：动作修正", "pose fix, warm key light"),
      frame("glass-stage", 5, "original", "original", "ready", 200, "tone-stage", "谢幕帧", "curtain call, glass floor"),
    ],
  },
  {
    id: "snow-station",
    category: "attention",
    name: "雪站换乘",
    shelf: "C-07",
    updated: "今天 09:35",
    summary: "雪地车站、多角色擦肩。角色证据不足，批量图先收纳为待确认。",
    roles: ["旅人", "售票员", "背景人群"],
    batches: ["batch-0615-A"],
    incoming: 4,
    attention: 4,
    frames: [
      frame("snow-station", 1, "original", "original", "ready", 210, "tone-snow", "站台远景", "snow station, wide shot"),
      frame("snow-station", 2, "hero-v1", "generated", "attention", 310, "tone-snow", "主角版 1：角色疑似混淆", "identity check required"),
      frame("snow-station", 3, "original", "original", "attention", 170, "tone-snow", "原图：脸部遮挡", "face blocked, evidence weak"),
      frame("snow-station", 4, "default-run", "generated", "attention", 260, "tone-neon", "默认生成：灯牌过亮", "sign light too strong"),
      frame("snow-station", 5, "hero-v2", "generated", "attention", 230, "tone-amber", "主角版 2：服装待确认", "outfit confirmation"),
    ],
  },
  {
    id: "amber-courtyard",
    category: "active",
    name: "琥珀庭院",
    shelf: "D-03",
    updated: "5 月 31 日",
    summary: "庭院、黄昏、角色服装状态变化。适合作为知识库确认样例。",
    roles: ["主角", "旧友"],
    batches: ["batch-0601-D", "batch-0602-A"],
    incoming: 3,
    attention: 1,
    frames: [
      frame("amber-courtyard", 1, "original", "original", "ready", 260, "tone-amber", "黄昏庭院", "amber courtyard, dusk"),
      frame("amber-courtyard", 2, "default-run", "generated", "ready", 310, "tone-amber", "默认生成：服装基准", "outfit baseline"),
      frame("amber-courtyard", 3, "hero-v1", "generated", "ready", 190, "tone-library", "主角版 1：道具特写", "prop close-up"),
      frame("amber-courtyard", 4, "rerun", "rerun", "attention", 280, "tone-rain", "单帧重跑：天气误入", "weather mismatch"),
      frame("amber-courtyard", 5, "original", "original", "ready", 220, "tone-amber", "告别镜头", "farewell frame"),
      frame("amber-courtyard", 6, "hero-v2", "generated", "ready", 330, "tone-stage", "主角版 2：情绪变体", "mood variant"),
    ],
  },
];

const state = {
  category: "all",
  version: "original",
  query: "",
  selectedScriptId: null,
  selectedFrameId: null,
  saveStatus: "",
};

function frame(scriptId, sequence, version, source, status, height, tone, title, prompt) {
  return {
    id: `${scriptId}-${sequence}-${version}-${title}`,
    scriptId,
    sequence,
    version,
    source,
    status,
    height,
    tone,
    title,
    prompt,
  };
}

function byId(id) {
  return document.getElementById(id);
}

function selectedScript() {
  return scripts.find((script) => script.id === state.selectedScriptId) || null;
}

function selectedFrame() {
  const script = selectedScript();
  if (!script) return null;
  return script.frames.find((frameItem) => frameItem.id === state.selectedFrameId) || null;
}

function normalized(value) {
  return value.trim().toLowerCase();
}

function versionOptions(script) {
  const base = [
    { id: "original", label: "原始剧本" },
    { id: "default-run", label: "默认生成" },
    { id: "hero-v1", label: "主角版 1" },
    { id: "hero-v2", label: "主角版 2" },
    { id: "rerun", label: "单帧重跑" },
    { id: "attention", label: "待处理" },
    { id: "all", label: "全部收纳" },
  ];
  return base
    .map((option) => ({
      ...option,
      count: script.frames.filter((item) => versionMatches(item, option.id)).length,
    }))
    .filter((option) => option.count > 0 || option.id === "all");
}

function versionMatches(frameItem, versionId) {
  if (versionId === "all") return true;
  if (versionId === "attention") return frameItem.status === "attention";
  return frameItem.version === versionId;
}

function scriptMatches(script) {
  if (state.category !== "all" && script.category !== state.category) return false;
  if (!state.query) return true;
  const haystack = [
    script.name,
    script.shelf,
    script.summary,
    script.updated,
    ...script.roles,
    ...script.batches,
    ...script.frames.flatMap((item) => [item.title, item.prompt, item.source, item.status, item.version]),
  ]
    .join("\n")
    .toLowerCase();
  return haystack.includes(state.query);
}

function frameMatches(frameItem) {
  if (!versionMatches(frameItem, state.version)) return false;
  if (!state.query) return true;
  return [frameItem.title, frameItem.prompt, frameItem.source, frameItem.status, frameItem.version]
    .join("\n")
    .toLowerCase()
    .includes(state.query);
}

function render() {
  const visibleScripts = scripts.filter(scriptMatches);
  const frameCount = scripts.reduce((sum, script) => sum + script.frames.length, 0);
  const incomingCount = scripts.reduce((sum, script) => sum + script.incoming, 0);
  const script = selectedScript();

  document.body.classList.toggle("detail-mode", Boolean(script));
  byId("metricScripts").textContent = scripts.length;
  byId("metricFrames").textContent = frameCount;
  byId("metricIncoming").textContent = incomingCount;
  byId("sidebarStatus").textContent = `${visibleScripts.length} 个剧本可见`;
  byId("controlPanel").hidden = Boolean(script);
  byId("categoryStrip").hidden = Boolean(script);
  byId("saveStatus").textContent = state.saveStatus;

  renderCategories();

  if (script) {
    ensureVersionAvailable(script);
    renderScriptDetail(script);
  } else {
    renderLibrary(visibleScripts);
  }
  renderDrawer();
}

function ensureVersionAvailable(script) {
  const options = versionOptions(script);
  if (!options.some((option) => option.id === state.version && option.count > 0)) {
    state.version = options[0]?.id || "all";
  }
}

function renderCategories() {
  byId("categoryStrip").innerHTML = categories
    .map((category, index) => {
      const matching = category.id === "all"
        ? scripts.length
        : scripts.filter((script) => script.category === category.id).length;
      return `
        <button class="category-card ${state.category === category.id ? "is-active" : ""}"
          data-category="${category.id}" data-index="${String(index + 1).padStart(2, "0")}" type="button">
          <div class="category-title">
            <span>${category.name}</span>
            <span class="category-count">${matching}</span>
          </div>
          <p>${category.description}</p>
          <div class="category-tags">
            ${category.tags.map((tag) => `<span class="mini-tag">${tag}</span>`).join("")}
          </div>
        </button>
      `;
    })
    .join("");
}

function renderLibrary(visibleScripts) {
  const content = byId("contentArea");
  if (visibleScripts.length === 0) {
    content.innerHTML = `<div class="empty-panel">没有匹配的剧本。换个分类或搜索词试试。</div>`;
    return;
  }

  content.innerHTML = `
    <div class="section-title-row">
      <div>
        <h2>剧本书架</h2>
        <p>原图与批量产线结果按剧本聚合，保留批次、帧序和角色线索。</p>
      </div>
      <span class="mini-tag">匹配 ${visibleScripts.length}</span>
    </div>
    <div class="script-grid">
      ${visibleScripts.map(renderScriptCard).join("")}
    </div>
  `;
}

function renderScriptCard(script) {
  const generated = script.frames.filter((item) => item.source === "generated").length;
  const originals = script.frames.filter((item) => item.source === "original").length;
  return `
    <button class="script-card" type="button" data-script="${script.id}">
      <div class="script-cover">
        <div class="cover-text">
          <strong>${script.name}</strong>
          <span>${script.shelf} / ${script.updated}</span>
        </div>
      </div>
      <div class="script-info">
        <h3>${script.name}</h3>
        <p>${script.summary}</p>
        <div class="script-stats">
          <div><strong>${originals}</strong><span>原始帧</span></div>
          <div><strong>${generated}</strong><span>生成图</span></div>
          <div><strong>${script.attention}</strong><span>待处理</span></div>
        </div>
        <div class="script-footer">
          ${script.roles.map((role) => `<span class="mini-tag">${role}</span>`).join("")}
        </div>
      </div>
    </button>
  `;
}

function renderScriptDetail(script) {
  const visibleFrames = script.frames.filter(frameMatches);
  const options = versionOptions(script);

  byId("contentArea").innerHTML = `
    <section class="detail-panel compact-detail">
      <div class="detail-top">
        <button class="back-button" type="button" data-back>返回馆区</button>
        <div class="detail-title">
          <h2>${script.name}</h2>
          <p>${script.summary}</p>
        </div>
        <span class="mini-tag">${script.shelf}</span>
      </div>
      <div class="version-switcher" aria-label="版本切换">
        ${options.map(renderVersionButton).join("")}
      </div>
    </section>
    <div class="section-title-row">
      <div>
        <h2>${currentVersionLabel(script)}</h2>
        <p>只显示当前版本/批次下的图片；切换上方标签即可看主角版本或原始剧本。</p>
      </div>
      <span class="mini-tag">显示 ${visibleFrames.length}</span>
    </div>
    ${visibleFrames.length === 0
      ? `<div class="empty-panel">当前版本下没有图片。</div>`
      : `<div class="masonry ${masonryClass()}">${visibleFrames.map(renderFrameCard).join("")}</div>`}
  `;
}

function renderVersionButton(option) {
  return `
    <button class="version-tab ${state.version === option.id ? "is-active" : ""}"
      type="button" data-version="${option.id}">
      <span>${option.label}</span>
      <strong>${option.count}</strong>
    </button>
  `;
}

function currentVersionLabel(script) {
  const option = versionOptions(script).find((item) => item.id === state.version);
  return option ? option.label : "当前版本";
}

function renderFrameCard(frameItem) {
  return `
    <button class="frame-card ${state.selectedFrameId === frameItem.id ? "is-selected" : ""}"
      type="button" data-frame="${frameItem.id}">
      <div class="mock-image ${frameItem.tone}" style="height:${frameItem.height}px">
        <div class="image-label">
          <strong>${frameItem.title}</strong>
          <span>${sourceLabel(frameItem.source)} / #${String(frameItem.sequence).padStart(2, "0")}</span>
        </div>
      </div>
      <div class="frame-meta">
        <div class="frame-badges">
          <span class="sequence-badge">#${String(frameItem.sequence).padStart(2, "0")}</span>
          <span class="source-badge source-${frameItem.source}">${sourceLabel(frameItem.source)}</span>
          ${frameItem.status === "attention" ? `<span class="status-badge status-warning">待处理</span>` : ""}
        </div>
        <div class="frame-title">${frameItem.title}</div>
        <div class="frame-prompt">${frameItem.prompt}</div>
      </div>
    </button>
  `;
}

function renderDrawer() {
  const drawer = byId("detailDrawer");
  const script = selectedScript();
  const frameItem = selectedFrame();

  if (!script) {
    drawer.innerHTML = `
      <div class="drawer-panel drawer-empty">
        <div>
          <h2>剧本详情</h2>
          <p>进入剧本后会显示收纳来源、版本批次和选中图片信息。</p>
        </div>
      </div>
    `;
    return;
  }

  if (!frameItem) {
    drawer.innerHTML = `
      <div class="drawer-panel">
        <h2>${script.name}</h2>
        <p>${script.summary}</p>
        <div class="drawer-section">
          <div class="drawer-label">收纳来源</div>
          <p>${script.batches.join(" / ")}</p>
        </div>
        <div class="drawer-section">
          <div class="drawer-label">角色</div>
          <div class="script-footer">${script.roles.map((role) => `<span class="mini-tag">${role}</span>`).join("")}</div>
        </div>
        <div class="drawer-section">
          <div class="drawer-label">当前版本</div>
          <p>${currentVersionLabel(script)}：帧级信息未选中。</p>
        </div>
      </div>
    `;
    return;
  }

  drawer.innerHTML = `
    <div class="drawer-panel">
      <div class="mock-image ${frameItem.tone}" style="height:210px">
        <div class="image-label">
          <strong>${frameItem.title}</strong>
          <span>${sourceLabel(frameItem.source)} / #${String(frameItem.sequence).padStart(2, "0")}</span>
        </div>
      </div>
      <div class="drawer-section">
        <h2>${frameItem.title}</h2>
        <div class="frame-badges">
          <span class="sequence-badge">#${String(frameItem.sequence).padStart(2, "0")}</span>
          <span class="source-badge source-${frameItem.source}">${sourceLabel(frameItem.source)}</span>
          ${frameItem.status === "attention" ? `<span class="status-badge status-warning">待处理</span>` : ""}
        </div>
      </div>
      <div class="drawer-section">
        <div class="drawer-label">归属剧本</div>
        <p>${script.name} / ${script.shelf}</p>
      </div>
      <div class="drawer-section">
        <div class="drawer-label">版本/批次</div>
        <p>${currentVersionLabel(script)} / ${script.batches.join(" / ")}</p>
      </div>
      <div class="drawer-section">
        <div class="drawer-label">Prompt 摘要</div>
        <p>${frameItem.prompt}</p>
      </div>
      <div class="drawer-actions">
        <button class="icon-button" type="button" data-lightbox="${frameItem.id}">全屏浏览</button>
        <button class="icon-button" type="button">送回工作台</button>
        <button class="icon-button" type="button">标记确认</button>
      </div>
    </div>
  `;
}

function sourceLabel(source) {
  if (source === "generated") return "批量新图";
  if (source === "rerun") return "单帧重跑";
  return "原始剧本";
}

function masonryClass() {
  const width = window.innerWidth;
  if (width < 760) return "columns-1";
  if (width < 1220) return "columns-2";
  return "columns-3";
}

function openLightbox(frameId) {
  const script = selectedScript();
  if (!script) return;
  const frameItem = script.frames.find((item) => item.id === frameId);
  if (!frameItem) return;
  byId("lightboxContent").innerHTML = `
    <div class="mock-image ${frameItem.tone}">
      <div class="image-label">
        <strong>${frameItem.title}</strong>
        <span>${sourceLabel(frameItem.source)} / #${String(frameItem.sequence).padStart(2, "0")}</span>
      </div>
    </div>
  `;
  byId("lightbox").classList.add("is-open");
  byId("lightbox").setAttribute("aria-hidden", "false");
}

function closeLightbox() {
  byId("lightbox").classList.remove("is-open");
  byId("lightbox").setAttribute("aria-hidden", "true");
}

function saveCategory() {
  const label = categories.find((category) => category.id === state.category)?.name || "当前分类";
  state.saveStatus = `已将导入剧本默认保存到「${label}」。`;
  render();
}

function newCategory() {
  const index = categories.length + 1;
  const id = `custom-${index}`;
  categories.push({
    id,
    name: `新分类 ${index}`,
    description: "导入剧本时自动创建，可后续重命名。",
    tags: ["新建", "导入"],
  });
  state.category = id;
  state.saveStatus = `已创建「新分类 ${index}」，后续导入可直接归入这里。`;
  render();
}

document.addEventListener("click", (event) => {
  const categoryButton = event.target.closest("[data-category]");
  if (categoryButton) {
    state.category = categoryButton.dataset.category;
    state.selectedScriptId = null;
    state.selectedFrameId = null;
    state.saveStatus = "";
    render();
    return;
  }

  const versionButton = event.target.closest("[data-version]");
  if (versionButton) {
    state.version = versionButton.dataset.version;
    state.selectedFrameId = null;
    render();
    return;
  }

  const scriptButton = event.target.closest("[data-script]");
  if (scriptButton) {
    state.selectedScriptId = scriptButton.dataset.script;
    state.selectedFrameId = null;
    state.version = "original";
    render();
    return;
  }

  if (event.target.closest("[data-back]")) {
    state.selectedScriptId = null;
    state.selectedFrameId = null;
    render();
    return;
  }

  const frameButton = event.target.closest("[data-frame]");
  if (frameButton) {
    state.selectedFrameId = frameButton.dataset.frame;
    render();
    openLightbox(frameButton.dataset.frame);
    return;
  }

  const lightboxButton = event.target.closest("[data-lightbox]");
  if (lightboxButton) {
    openLightbox(lightboxButton.dataset.lightbox);
  }
});

byId("searchInput").addEventListener("input", (event) => {
  state.query = normalized(event.target.value);
  state.selectedFrameId = null;
  render();
});

byId("saveCategoryButton").addEventListener("click", saveCategory);
byId("newCategoryButton").addEventListener("click", newCategory);
byId("lightboxClose").addEventListener("click", closeLightbox);
byId("lightbox").addEventListener("click", (event) => {
  if (event.target.id === "lightbox") closeLightbox();
});
window.addEventListener("resize", render);

render();
