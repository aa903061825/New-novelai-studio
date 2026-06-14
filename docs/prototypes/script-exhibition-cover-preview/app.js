const variants = {
  A: {
    name: "大封面网格",
    description:
      "每个剧本像画廊专辑一样先看封面，适合剧本数量中等、想靠视觉记忆快速找回批次的主视图。",
    implementation:
      "Flutter 实装：给 ScriptExhibitionScript 增加 coverItem 计算值，卡片顶部用 Image.file + 渐变遮罩。"
  },
  B: {
    name: "胶片缩略带",
    description:
      "封面放左侧，右侧补充 4 个帧色块和更多统计；适合保留工作台的信息密度，又比纯文字更容易扫。",
    implementation:
      "Flutter 实装：卡片用 Row 布局，封面固定宽度，额外展示 cover 来源与最近 4 帧缩略信息。"
  },
  C: {
    name: "密集书架",
    description:
      "封面变成书脊式窄图，卡片高度更低；适合你截图里那种一次看几十个剧本的场景。",
    implementation:
      "Flutter 实装：保留现有 6 列左右密度，用封面窄栏替代小图标和纯文字标题。"
  },
  D: {
    name: "全封面墙",
    description:
      "把内容区变成封面海报墙，标题和统计都压在图片上；适合把剧本展览室当故事库浏览。",
    implementation:
      "Flutter 实装：主列表改为封面优先 Grid，操作按钮仅在悬停/选中时浮现，顶部筛选保持轻量。"
  },
  E: {
    name: "封面墙 + 检查器",
    description:
      "左侧仍是沉浸封面墙，右侧固定显示选中剧本的批次、角色、封面来源和快捷动作。",
    implementation:
      "Flutter 实装：Grid + 右侧详情栏；点封面只切换选中，不直接进入详情页，双击或按钮再打开。"
  }
};

const scripts = [
  script("rain", "雨夜档案", "A-02", "active", "今天 14:20", "tone-rain", {
    image: "sample-images/actual-cover-1.png",
    summary: "雨夜、图书馆、双主角追踪线。第二批跑图正在回写。",
    roles: ["女主", "协助者", "临时角色"],
    batches: ["batch-0614-A", "batch-0614-B"],
    original: 42,
    generated: 31,
    needs: 2,
    cover: {
      best: ["新图封面", "默认生成 #18"],
      original: ["原图封面", "原始帧 #01"],
      latest: ["最新封面", "主角版 B #31"]
    }
  }),
  script("stage", "玻璃舞台", "B-11", "archived", "昨天 22:08", "tone-stage", {
    image: "sample-images/actual-cover-2.png",
    summary: "舞台、镜面、换装段落。全部生成图已完成批次收纳。",
    roles: ["舞台主角", "摄影机"],
    batches: ["batch-0609-C"],
    original: 18,
    generated: 26,
    needs: 0,
    cover: {
      best: ["收纳封面", "精选画廊 #04"],
      original: ["原图封面", "镜面开场"],
      latest: ["最新封面", "动作修正 #26"]
    }
  }),
  script("snow", "雪站换乘", "C-07", "needs", "今天 09:35", "tone-snow", {
    summary: "雪地车站、多角色擦肩。角色证据不足，需要人工确认。",
    roles: ["旅人", "售票员", "背景人群"],
    batches: ["batch-0615-A"],
    original: 24,
    generated: 9,
    needs: 4,
    cover: {
      best: ["待处理封面", "身份混淆 #02"],
      original: ["原图封面", "站台远景"],
      latest: ["最新封面", "灯牌过曝 #09"]
    }
  }),
  script("amber", "琥珀庭院", "D-03", "active", "5 月 31 日", "tone-amber", {
    summary: "庭院、黄昏、服装状态变化。适合作为知识库确认样例。",
    roles: ["主角", "旧友"],
    batches: ["batch-0601-D", "batch-0602-A"],
    original: 36,
    generated: 44,
    needs: 1,
    cover: {
      best: ["新图封面", "服装基准 #12"],
      original: ["原图封面", "黄昏庭院"],
      latest: ["最新封面", "情绪变体 #44"]
    }
  }),
  script("neon", "霓虹诊室", "E-14", "archived", "5 月 28 日", "tone-neon", {
    summary: "室内冷光、设备特写、角色状态切换。已完成复盘。",
    roles: ["护士", "访客"],
    batches: ["batch-0528-B"],
    original: 21,
    generated: 33,
    needs: 0,
    cover: {
      best: ["收纳封面", "冷光主视觉"],
      original: ["原图封面", "走廊入口"],
      latest: ["最新封面", "设备特写 #33"]
    }
  }),
  script("crimson", "绯红走廊", "F-06", "needs", "今天 11:02", "tone-crimson", {
    summary: "长走廊、逆光、色彩偏移。需要重新选择封面和确认主角版本。",
    roles: ["主角", "影子"],
    batches: ["batch-0616-A"],
    original: 30,
    generated: 12,
    needs: 5,
    cover: {
      best: ["待处理封面", "色偏帧 #08"],
      original: ["原图封面", "走廊远景"],
      latest: ["最新封面", "重跑 #12"]
    }
  }),
  script("greenhouse", "温室记录", "G-09", "active", "昨天 16:44", "tone-green", {
    summary: "温室、植物遮挡、前后景切换。正在补角色证据。",
    roles: ["研究员", "助手"],
    batches: ["batch-0612-F"],
    original: 29,
    generated: 18,
    needs: 3,
    cover: {
      best: ["新图封面", "叶影构图 #10"],
      original: ["原图封面", "温室入口"],
      latest: ["最新封面", "补帧 #18"]
    }
  }),
  script("library", "银狼图书馆", "H-01", "archived", "5 月 25 日", "tone-library", {
    summary: "书架、银色光照、单角色独白。默认版本已经收纳。",
    roles: ["银狼", "旁白"],
    batches: ["batch-0525-A"],
    original: 27,
    generated: 39,
    needs: 0,
    cover: {
      best: ["收纳封面", "书架主视觉"],
      original: ["原图封面", "开场帧"],
      latest: ["最新封面", "独白特写 #39"]
    }
  })
];

const state = {
  variant: new URLSearchParams(location.search).get("variant") || "A",
  category: "all",
  coverPolicy: "best",
  query: "",
  selectedScriptId: "rain"
};

function script(id, title, shelf, category, updated, tone, extra) {
  return {
    id,
    title,
    shelf,
    category,
    updated,
    tone,
    ...extra
  };
}

function byId(id) {
  return document.getElementById(id);
}

function visibleScripts() {
  const q = state.query.trim().toLowerCase();
  return scripts.filter((item) => {
    if (state.category !== "all" && item.category !== state.category) {
      return false;
    }
    if (!q) return true;
    const cover = item.cover[state.coverPolicy];
    return [
      item.title,
      item.shelf,
      item.summary,
      item.updated,
      item.category,
      ...item.roles,
      ...item.batches,
      ...cover
    ]
      .join("\n")
      .toLowerCase()
      .includes(q);
  });
}

function render() {
  if (!variants[state.variant]) state.variant = "A";
  const items = visibleScripts();
  byId("metricScripts").textContent = scripts.length;
  byId("metricImages").textContent = scripts.reduce(
    (sum, item) => sum + item.original + item.generated,
    0
  );
  byId("metricNeeds").textContent = scripts.reduce((sum, item) => sum + item.needs, 0);
  renderIntro();
  renderCards(items);
  renderSwitcher();
}

function renderIntro() {
  const variant = variants[state.variant];
  byId("variantIntro").innerHTML = `
    <div>
      <h2>${state.variant}. ${variant.name}</h2>
      <p>${variant.description}</p>
    </div>
    <div class="implementation">${variant.implementation}</div>
  `;
}

function renderCards(items) {
  const content = byId("contentArea");
  if (items.length === 0) {
    content.innerHTML = `<div class="empty">没有匹配的剧本。换个分类或搜索词试试。</div>`;
    return;
  }
  if (state.variant === "D") {
    content.innerHTML = renderCoverWall(items);
    return;
  }
  if (state.variant === "E") {
    content.innerHTML = renderInspectorWall(items);
    return;
  }
  content.innerHTML = `
    <div class="cover-grid variant-${state.variant.toLowerCase()}">
      ${items.map((item, index) => renderCard(item, index)).join("")}
    </div>
  `;
}

function renderCard(item, index) {
  if (state.variant === "B") return renderFilmCard(item);
  if (state.variant === "C") return renderShelfCard(item);
  return renderHeroCard(item, index);
}

function renderCoverWall(items) {
  return `
    <div class="cover-theater">
      <div class="theater-topline">
        <strong>${items.length} 个剧本封面</strong>
        <span>单击封面可预选，Enter/打开按钮再进入剧本详情。</span>
      </div>
      <div class="poster-wall">
        ${items.map((item, index) => renderPosterCard(item, index)).join("")}
      </div>
    </div>
  `;
}

function renderInspectorWall(items) {
  const selected =
    items.find((item) => item.id === state.selectedScriptId) || items[0];
  state.selectedScriptId = selected.id;
  return `
    <div class="inspector-layout">
      <div class="poster-wall compact">
        ${items.map((item, index) => renderPosterCard(item, index, true)).join("")}
      </div>
      ${renderInspector(selected)}
    </div>
  `;
}

function renderPosterCard(item, index, compact = false) {
  const [sourceLabel, frameLabel] = coverData(item);
  const total = item.original + item.generated;
  return `
    <button class="poster-card ${item.tone} ${item.image ? "real-cover" : ""} ${compact ? "compact" : ""} ${
      state.selectedScriptId === item.id ? "is-selected" : ""
    } ${index === 0 && !compact ? "is-wide" : ""}" ${coverStyle(item)} type="button" data-select-script="${item.id}">
      <div class="poster-shade"></div>
      <div class="poster-status">
        <span class="${item.needs > 0 ? "warn" : "ok"}">${item.needs > 0 ? `${item.needs} 需处理` : "已归档"}</span>
        <span>${sourceLabel}</span>
      </div>
      <div class="poster-copy">
        <h3>${item.title}</h3>
        <p>${frameLabel}</p>
        <div class="poster-meta">
          <strong>${total}</strong><span>全部图</span>
          <strong>${item.generated}</strong><span>新图</span>
          <strong>${item.shelf}</strong><span>${item.updated}</span>
        </div>
      </div>
    </button>
  `;
}

function renderInspector(item) {
  const [sourceLabel, frameLabel] = coverData(item);
  const total = item.original + item.generated;
  return `
    <aside class="cover-inspector">
      <div class="inspector-cover ${item.tone} ${item.image ? "real-cover" : ""}" ${coverStyle(item)}>
        <div class="poster-shade"></div>
        <div class="poster-copy">
          <h2>${item.title}</h2>
          <p>${sourceLabel} / ${frameLabel}</p>
        </div>
      </div>
      <div class="inspector-section">
        <span class="section-label">收纳状态</span>
        <div class="inspector-stats">
          <div><strong>${total}</strong><span>全部图</span></div>
          <div><strong>${item.original}</strong><span>原图</span></div>
          <div><strong>${item.generated}</strong><span>新图</span></div>
          <div><strong>${item.needs}</strong><span>需处理</span></div>
        </div>
      </div>
      <div class="inspector-section">
        <span class="section-label">摘要</span>
        <p>${item.summary}</p>
      </div>
      <div class="inspector-section">
        <span class="section-label">角色</span>
        <div class="badge-row">${item.roles
          .map((role) => `<span class="badge">${role}</span>`)
          .join("")}</div>
      </div>
      <div class="inspector-section">
        <span class="section-label">批次</span>
        <p>${item.batches.join(" / ")}</p>
      </div>
      <div class="inspector-actions">
        <button type="button">打开剧本</button>
        <button type="button">发送工作台</button>
        <button type="button">指定封面</button>
      </div>
    </aside>
  `;
}

function coverData(item) {
  return item.cover[state.coverPolicy] || item.cover.best;
}

function coverStyle(item) {
  if (!item.image) return "";
  return `style="--cover-image: url('${item.image}')"`;
}

function renderCover(item) {
  const [sourceLabel, frameLabel] = coverData(item);
  return `
    <div class="cover ${item.tone} ${item.image ? "real-cover" : ""}" ${coverStyle(item)}>
      <div class="cover-label">
        <div class="badge-row">
          <span class="badge ${sourceLabel.includes("待处理") ? "warn" : "new"}">${sourceLabel}</span>
          <span class="badge">${item.shelf}</span>
        </div>
        <strong>${item.title}</strong>
        <span>${frameLabel}</span>
      </div>
    </div>
  `;
}

function renderHeroCard(item, index) {
  return `
    <article class="script-card ${index === 0 ? "featured" : ""}">
      ${renderCover(item)}
      <div class="card-body">
        ${renderTitle(item)}
        <p>${item.summary}</p>
        ${renderStats(item)}
        ${renderFooter(item)}
      </div>
    </article>
  `;
}

function renderFilmCard(item) {
  return `
    <article class="script-card">
      ${renderCover(item)}
      <div class="card-body">
        ${renderTitle(item)}
        <p>${item.summary}</p>
        <div class="film-strip" aria-hidden="true">
          <span class="film-frame ${item.tone}"></span>
          <span class="film-frame tone-library"></span>
          <span class="film-frame tone-neon"></span>
          <span class="film-frame tone-amber"></span>
        </div>
        ${renderStats(item, true)}
        ${renderFooter(item)}
      </div>
    </article>
  `;
}

function renderShelfCard(item) {
  return `
    <article class="script-card">
      ${renderCover(item)}
      <div class="card-body">
        ${renderTitle(item)}
        <p>${item.summary}</p>
        ${renderStats(item, true)}
        <div class="source-line">${coverData(item).join(" / ")}</div>
        <div class="actions">
          <button type="button" aria-label="打开剧本">↗</button>
        </div>
      </div>
    </article>
  `;
}

function renderTitle(item) {
  return `
    <div class="title-row">
      <h3>${item.title}</h3>
      <span>${item.updated}</span>
    </div>
  `;
}

function renderStats(item, includeTotal = false) {
  const total = item.original + item.generated;
  return `
    <div class="stats">
      ${includeTotal ? `<div><strong>${total}</strong><span>全部图</span></div>` : ""}
      <div><strong>${item.original}</strong><span>原图</span></div>
      <div><strong>${item.generated}</strong><span>新图</span></div>
      <div><strong>${item.needs}</strong><span>需处理</span></div>
    </div>
  `;
}

function renderFooter(item) {
  return `
    <div class="badge-row">
      ${item.roles.map((role) => `<span class="badge">${role}</span>`).join("")}
      <span class="badge">${item.batches[0]}</span>
    </div>
    <div class="actions">
      <button type="button" aria-label="发送到剧本工作台">▷</button>
      <button type="button" aria-label="编辑剧本">✎</button>
      <button type="button" aria-label="删除记录">⌫</button>
    </div>
  `;
}

function renderSwitcher() {
  const variant = variants[state.variant];
  byId("variantLabel").textContent = `${state.variant} / ${variant.name}`;
  document.querySelectorAll("[data-category]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.category === state.category);
  });
  document.querySelectorAll("[data-cover-policy]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.coverPolicy === state.coverPolicy);
  });
}

function setVariant(next) {
  state.variant = next;
  const url = new URL(location.href);
  url.searchParams.set("variant", next);
  history.replaceState(null, "", url);
  render();
}

function cycleVariant(direction) {
  const keys = Object.keys(variants);
  const current = keys.indexOf(state.variant);
  const next = keys[(current + direction + keys.length) % keys.length];
  setVariant(next);
}

document.addEventListener("click", (event) => {
  const category = event.target.closest("[data-category]");
  if (category) {
    state.category = category.dataset.category;
    render();
    return;
  }
  const policy = event.target.closest("[data-cover-policy]");
  if (policy) {
    state.coverPolicy = policy.dataset.coverPolicy;
    render();
    return;
  }
  const script = event.target.closest("[data-select-script]");
  if (script) {
    state.selectedScriptId = script.dataset.selectScript;
    render();
  }
});

document.addEventListener("keydown", (event) => {
  const active = document.activeElement;
  const isTyping =
    active &&
    (active.tagName === "INPUT" ||
      active.tagName === "TEXTAREA" ||
      active.isContentEditable);
  if (isTyping) return;
  if (event.key === "ArrowLeft") cycleVariant(-1);
  if (event.key === "ArrowRight") cycleVariant(1);
});

byId("searchInput").addEventListener("input", (event) => {
  state.query = event.target.value;
  render();
});

byId("prevVariant").addEventListener("click", () => cycleVariant(-1));
byId("nextVariant").addEventListener("click", () => cycleVariant(1));

render();
