const INITIAL_TAGS = [
  { id: "tag-1", source: "1girl", translation: "单人女孩", category: "character", group: "角色", weight: 1 },
  { id: "tag-2", source: "blue eyes", translation: "蓝色眼睛", category: "character", group: "角色", weight: 1 },
  { id: "tag-3", source: "长发", translation: "long hair", category: "character", group: "角色", weight: 1 },
  { id: "tag-4", source: "cat ears", translation: "猫耳", category: "character", group: "角色", weight: 1 },
  { id: "tag-5", source: "white shirt", translation: "白色上衣", category: "clothing", group: "服装/身体", weight: 1 },
  { id: "tag-6", source: "pleated skirt", translation: "百褶裙", category: "clothing", group: "服装/身体", weight: 1.1 },
  { id: "tag-7", source: "silver ribbon", translation: "银色缎带", category: "clothing", group: "服装/身体", weight: 1 },
  { id: "tag-8", source: "looking at viewer", translation: "看向观众", category: "scene", group: "画面", weight: 1 },
  { id: "tag-9", source: "upper body", translation: "上半身", category: "scene", group: "画面", weight: 1 },
  { id: "tag-10", source: "simple background", translation: "简洁背景", category: "scene", group: "画面", weight: 1 },
  { id: "tag-11", source: "soft shading", translation: "柔和上色", category: "style", group: "风格", weight: 1 },
  { id: "tag-12", source: "warm light", translation: "暖色光", category: "style", group: "风格", weight: 0.85 },
];

const CATEGORY_LABELS = {
  character: "角色",
  clothing: "服装/身体",
  scene: "画面",
  style: "风格",
  other: "未分类",
};

const GROUP_ORDER = ["character", "clothing", "scene", "style", "other"];

const state = {
  tags: cloneTags(INITIAL_TAGS),
  filter: "all",
  query: "",
  layout: "grouped",
  selected: new Set(),
  translated: new Set(),
  loading: new Set(),
  failed: new Set(),
  showTranslations: false,
  translating: false,
  toastTimer: null,
};

function cloneTags(tags) {
  return tags.map((tag) => ({ ...tag }));
}

function byId(id) {
  return document.getElementById(id);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function normalize(value) {
  return value.trim().toLocaleLowerCase();
}

function visibleTags() {
  const query = normalize(state.query);
  return state.tags.filter((tag) => {
    const categoryMatches = state.filter === "all" || tag.category === state.filter;
    if (!categoryMatches) return false;
    if (!query) return true;
    return [tag.source, tag.translation, tag.group, CATEGORY_LABELS[tag.category]]
      .filter(Boolean)
      .join(" ")
      .toLocaleLowerCase()
      .includes(query);
  });
}

function formatWeight(weight) {
  if (!weight || weight === 1) return "";
  return `×${Number(weight).toFixed(2).replace(/\.00$/, "")}`;
}

function promptValue(tag) {
  if (!tag.weight || tag.weight === 1) return tag.source;
  return `${Number(tag.weight).toFixed(2).replace(/\.00$/, "")}:: ${tag.source} ::`;
}

function promptText() {
  return state.tags.map(promptValue).join(", ");
}

function translationStatus(tag) {
  if (state.loading.has(tag.id)) return "loading";
  if (state.failed.has(tag.id)) return "missing";
  if (state.translated.has(tag.id)) return "translated";
  return "idle";
}

function translationLabel(tag) {
  const status = translationStatus(tag);
  if (status === "loading") return "翻译中…";
  if (status === "missing") return "翻译失败 · 点击重试";
  if (status === "translated" && state.showTranslations) return tag.translation || "暂无译文";
  return "按需翻译";
}

function translationStatusBadge(tag) {
  const status = translationStatus(tag);
  if (status === "loading") return '<span class="tag-status-badge status-loading">处理中</span>';
  if (status === "missing") return '<span class="tag-status-badge status-missing">需重试</span>';
  if (status === "translated") return '<span class="tag-status-badge status-translated">已翻译</span>';
  return '<span class="tag-status-badge">未翻译</span>';
}

function tagCard(tag) {
  const status = translationStatus(tag);
  const selected = state.selected.has(tag.id);
  const visibleTranslation = status === "translated" && state.showTranslations;
  const translationClass = [
    "translation-label",
    visibleTranslation ? "is-visible" : "",
    status === "loading" ? "is-loading" : "",
    status === "missing" ? "is-missing" : "",
  ]
    .filter(Boolean)
    .join(" ");
  const cardClass = [
    "tag-card",
    selected ? "is-selected" : "",
    status === "loading" ? "is-loading" : "",
    status === "missing" ? "is-missing" : "",
  ]
    .filter(Boolean)
    .join(" ");
  const weight = formatWeight(tag.weight);

  return `
    <article class="${cardClass}" data-tag-id="${escapeHtml(tag.id)}" data-category="${escapeHtml(tag.category)}" data-group-label="${escapeHtml(tag.group)}">
      <button class="tag-select" type="button" data-select-tag="${escapeHtml(tag.id)}" aria-pressed="${selected ? "true" : "false"}" aria-label="选择标签 ${escapeHtml(tag.source)}">
        <span class="tag-source-row">
          <span class="source-label">${escapeHtml(tag.source)}</span>
        </span>
        <span class="${translationClass}">${escapeHtml(translationLabel(tag))}</span>
      </button>
      <span class="tag-meta">
        ${weight ? `<span class="weight-badge">${escapeHtml(weight)}</span>` : ""}
        ${translationStatusBadge(tag)}
      </span>
      <button class="tag-remove" type="button" data-remove-tag="${escapeHtml(tag.id)}" aria-label="删除标签 ${escapeHtml(tag.source)}" title="删除标签">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
          <path d="M6 6l12 12M18 6 6 18" stroke-linecap="round" />
        </svg>
      </button>
    </article>
  `;
}

function renderGrouped(tags) {
  const groups = GROUP_ORDER.map((category) => ({
    category,
    label: CATEGORY_LABELS[category],
    tags: tags.filter((tag) => tag.category === category),
  })).filter((group) => group.tags.length > 0);

  if (groups.length === 0) return emptyState();

  return groups
    .map(
      (group) => `
        <section class="tag-section" aria-labelledby="tag-section-${group.category}">
          <div class="tag-section-heading">
            <strong id="tag-section-${group.category}">
              <span class="section-marker section-marker-${group.category}" aria-hidden="true"></span>
              ${escapeHtml(group.label)}
            </strong>
            <span class="tag-section-count">${group.tags.length} 项</span>
          </div>
          <div class="tag-grid">${group.tags.map(tagCard).join("")}</div>
        </section>
      `,
    )
    .join("");
}

function renderSourceOrder(tags) {
  if (tags.length === 0) return emptyState();
  return `<div class="source-order-list">${tags.map(tagCard).join("")}</div>`;
}

function emptyState() {
  return `
    <div class="empty-state">
      <div>
        <strong>没有匹配的标签</strong>
        <span>换一个关键词，或从下方添加新标签。</span>
      </div>
    </div>
  `;
}

function renderTagBoard() {
  const tags = visibleTags();
  byId("tagBoard").innerHTML = state.layout === "grouped" ? renderGrouped(tags) : renderSourceOrder(tags);
}

function renderFilterCounts() {
  document.querySelectorAll("[data-filter]").forEach((button) => {
    const filter = button.dataset.filter;
    const count = filter === "all" ? state.tags.length : state.tags.filter((tag) => tag.category === filter).length;
    const countElement = button.querySelector("span");
    if (countElement) countElement.textContent = String(count);
    button.classList.toggle("is-active", state.filter === filter);
  });
}

function renderPrompt() {
  const prompt = state.tags.map((tag) => `<span class="prompt-token">${escapeHtml(promptValue(tag))}</span>`).join(", ");
  byId("promptPreview").innerHTML = prompt || '<span class="prompt-placeholder">暂无 Prompt</span>';
  byId("promptTokenCount").textContent = String(state.tags.length);
  byId("tagCount").textContent = `${state.tags.length} 个标签`;
}

function renderTranslationState() {
  const translatedCount = state.translated.size;
  const total = state.tags.length;
  const progress = total === 0 ? 0 : Math.round((translatedCount / total) * 100);
  const stateIcon = byId("translationStateIcon");
  const title = byId("translationStateTitle");
  const text = byId("translationStateText");
  const actionButton = byId("translateAllButton");
  const actionLabel = byId("translateAllLabel");
  const progressTrack = byId("translationProgress");

  stateIcon.className = "state-icon";
  if (state.translating) {
    stateIcon.classList.add("state-icon-loading");
    stateIcon.innerHTML = '<span class="loading-spinner" aria-hidden="true"></span>';
    title.textContent = "正在翻译";
    text.textContent = `已完成 ${translatedCount} / ${total} · 不影响编辑`;
    actionLabel.textContent = "翻译中…";
    actionButton.disabled = true;
    progressTrack.hidden = false;
  } else if (translatedCount === total && total > 0) {
    stateIcon.classList.add("state-icon-ready");
    stateIcon.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="m5 12.5 4.2 4.2L19 7" stroke-linecap="round" stroke-linejoin="round" /></svg>';
    title.textContent = state.showTranslations ? "译文辅助已开启" : "译文已缓存";
    text.textContent = state.showTranslations ? "原文仍是主信息 · 译文仅作第二行" : "点击显示译文 · 不影响发送";
    actionLabel.textContent = state.showTranslations ? "隐藏译文" : "显示译文";
    actionButton.disabled = false;
    progressTrack.hidden = true;
  } else if (translatedCount > 0) {
    stateIcon.classList.add("state-icon-ready");
    stateIcon.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M4 12h16M12 4v16" stroke-linecap="round" /></svg>';
    title.textContent = "部分译文已缓存";
    text.textContent = `已完成 ${translatedCount} / ${total} · 可继续翻译`;
    actionLabel.textContent = "继续翻译";
    actionButton.disabled = false;
    progressTrack.hidden = false;
  } else {
    stateIcon.classList.add("state-icon-native");
    stateIcon.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M5 12.5 9.2 17 19 7" stroke-linecap="round" stroke-linejoin="round" /></svg>';
    title.textContent = "原文优先";
    text.textContent = "译文未加载 · 不影响发送";
    actionLabel.textContent = "一键翻译";
    actionButton.disabled = false;
    progressTrack.hidden = true;
  }

  byId("translationProgressBar").style.width = `${progress}%`;
  byId("translationMeterFill").style.width = `${progress}%`;
  byId("translationCount").textContent = `${translatedCount} / ${total}`;
  byId("translationSummary").textContent = translationSummary(translatedCount, total);
}

function translationSummary(translatedCount, total) {
  if (state.translating) return `正在逐项请求译文，已完成 ${translatedCount} 项。编辑与发送都不会被阻塞。`;
  if (translatedCount === 0) return "还没有请求翻译。需要查看中文含义时，再点击上方“一键翻译”。";
  if (translatedCount < total) return `已有 ${translatedCount} 项进入辅助层，其余标签仍保持原文显示。`;
  return state.showTranslations ? "译文已显示在标签第二行；Prompt 预览仍保持原始标签。" : "译文已缓存但未显示；点击“显示译文”即可查看。";
}

function renderSelectionToolbar() {
  const selectedCount = state.selected.size;
  const toolbar = byId("selectionToolbar");
  toolbar.hidden = selectedCount === 0;
  byId("selectionSummary").textContent = `已选 ${selectedCount} 项`;
  const visible = visibleTags();
  const allVisibleSelected = visible.length > 0 && visible.every((tag) => state.selected.has(tag.id));
  byId("selectVisibleButton").textContent = allVisibleSelected ? "取消当前结果" : "全选当前结果";
  byId("translateSelectedButton").disabled = state.translating;
}

function renderInspector() {
  const selectedTags = state.tags.filter((tag) => state.selected.has(tag.id));
  const badge = byId("inspectorSelectionCount");
  const content = byId("inspectorContent");
  badge.textContent = selectedTags.length > 0 ? `${selectedTags.length} 项` : "未选择";

  if (selectedTags.length === 0) {
    content.className = "inspector-empty";
    content.innerHTML = `
      <div class="empty-icon" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7">
          <path d="M6 5h12v14H6z" />
          <path d="M9 9h6M9 13h4" stroke-linecap="round" />
        </svg>
      </div>
      <strong>选择一个标签查看详情</strong>
      <span>也可以多选后批量翻译。</span>
    `;
    return;
  }

  if (selectedTags.length > 1) {
    const untranslated = selectedTags.filter((tag) => !state.translated.has(tag.id)).length;
    content.className = "inspector-detail";
    content.innerHTML = `
      <div>
        <span class="detail-label">批量选择</span>
        <div class="detail-source">${selectedTags.length} 个标签</div>
      </div>
      <div class="detail-grid">
        <div class="detail-stat"><span>待翻译</span><strong>${untranslated} 项</strong></div>
        <div class="detail-stat"><span>当前 Prompt</span><strong>保持不变</strong></div>
      </div>
      <button class="button button-soft" type="button" data-inspector-translate="selected">翻译选中标签</button>
    `;
    return;
  }

  const tag = selectedTags[0];
  const status = translationStatus(tag);
  const statusText = status === "translated" ? "已缓存" : status === "loading" ? "翻译中" : status === "missing" ? "需重试" : "未请求";
  content.className = "inspector-detail";
  content.innerHTML = `
    <div>
      <span class="detail-label">原始标签</span>
      <div class="detail-source">${escapeHtml(tag.source)}</div>
    </div>
    <div class="detail-grid">
      <div class="detail-stat"><span>分类</span><strong>${escapeHtml(tag.group)}</strong></div>
      <div class="detail-stat"><span>翻译状态</span><strong>${statusText}</strong></div>
    </div>
    <div>
      <span class="detail-label">辅助译文</span>
      <div class="side-copy">${status === "translated" ? escapeHtml(tag.translation || "暂无译文") : "还没有译文，不会影响 Prompt。"}</div>
    </div>
    <button class="button ${status === "translated" ? "button-quiet" : "button-soft"}" type="button" data-inspector-translate="${escapeHtml(tag.id)}">
      ${status === "translated" ? "重新翻译此项" : status === "missing" ? "重试此项" : "翻译此项"}
    </button>
  `;
}

function render() {
  renderTagBoard();
  renderFilterCounts();
  renderPrompt();
  renderTranslationState();
  renderSelectionToolbar();
  renderInspector();
  document.querySelectorAll("[data-layout]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.layout === state.layout);
  });
}

function setSelected(id, selected) {
  if (selected) state.selected.add(id);
  else state.selected.delete(id);
}

function toggleTagSelection(id) {
  setSelected(id, !state.selected.has(id));
  render();
}

function selectVisible() {
  const tags = visibleTags();
  const allSelected = tags.length > 0 && tags.every((tag) => state.selected.has(tag.id));
  tags.forEach((tag) => setSelected(tag.id, !allSelected));
  render();
}

function removeTag(id) {
  const index = state.tags.findIndex((tag) => tag.id === id);
  if (index < 0) return;
  const [removed] = state.tags.splice(index, 1);
  state.selected.delete(id);
  state.translated.delete(id);
  state.loading.delete(id);
  state.failed.delete(id);
  render();
  showToast(`已删除“${removed.source}”`);
}

function translationDelay() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 70 : 260;
}

function wait(ms) {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

function fallbackTranslation(tag) {
  return tag.translation || `辅助译文：${tag.source}`;
}

async function translateTags(ids) {
  if (state.translating) return;
  const targets = ids
    .map((id) => state.tags.find((tag) => tag.id === id))
    .filter(Boolean)
    .filter((tag) => !state.translated.has(tag.id));
  if (targets.length === 0) {
    state.showTranslations = true;
    render();
    showToast("选中的标签已经有译文了。");
    return;
  }

  state.translating = true;
  state.showTranslations = true;
  targets.forEach((tag) => {
    state.loading.add(tag.id);
    state.failed.delete(tag.id);
  });
  render();

  for (const tag of targets) {
    await wait(translationDelay());
    state.loading.delete(tag.id);
    if (!tag.translation) {
      state.failed.add(tag.id);
    } else {
      tag.translation = fallbackTranslation(tag);
      state.translated.add(tag.id);
    }
    render();
  }

  state.translating = false;
  render();
  const failed = targets.filter((tag) => state.failed.has(tag.id)).length;
  if (failed > 0) showToast(`${targets.length - failed} 项已完成，${failed} 项需要重试。`);
  else showToast(`已翻译 ${targets.length} 项，Prompt 内容保持不变。`);
}

function handleTranslateAll() {
  const total = state.tags.length;
  if (state.translated.size === total && total > 0 && !state.translating) {
    state.showTranslations = !state.showTranslations;
    render();
    showToast(state.showTranslations ? "已显示辅助译文。" : "已隐藏辅助译文，原文保持不变。");
    return;
  }
  translateTags(state.tags.map((tag) => tag.id));
}

function handleTranslateSelected() {
  translateTags([...state.selected]);
}

function handleInspectorTranslate(value) {
  if (value === "selected") {
    handleTranslateSelected();
    return;
  }
  state.translated.delete(value);
  translateTags([value]);
}

function addTags(value) {
  const entries = value
    .split(/[，,\n]/)
    .map((item) => item.trim())
    .filter(Boolean);
  if (entries.length === 0) {
    showToast("请输入至少一个标签。");
    return;
  }

  const existing = new Set(state.tags.map((tag) => normalize(tag.source)));
  const additions = entries.filter((entry) => !existing.has(normalize(entry)));
  additions.forEach((entry, index) => {
    state.tags.push({
      id: `custom-${Date.now()}-${index}`,
      source: entry,
      translation: "",
      category: "other",
      group: "未分类",
      weight: 1,
    });
  });
  render();
  if (additions.length === 0) showToast("这些标签已经存在。");
  else showToast(`已添加 ${additions.length} 个标签，默认保持原文。`);
}

async function copyText(value) {
  try {
    await navigator.clipboard.writeText(value);
    showToast("Prompt 已复制。");
  } catch (_) {
    showToast("当前预览环境无法访问剪贴板，请手动复制。\n");
  }
}

function showToast(message) {
  const toast = byId("toast");
  toast.textContent = message;
  toast.classList.add("is-visible");
  window.clearTimeout(state.toastTimer);
  state.toastTimer = window.setTimeout(() => toast.classList.remove("is-visible"), 2600);
}

function resetSample() {
  state.tags = cloneTags(INITIAL_TAGS);
  state.filter = "all";
  state.query = "";
  state.layout = "grouped";
  state.selected.clear();
  state.translated.clear();
  state.loading.clear();
  state.failed.clear();
  state.showTranslations = false;
  state.translating = false;
  byId("searchInput").value = "";
  byId("addTagInput").value = "";
  render();
  showToast("已恢复中文原生模式样本。");
}

function bindEvents() {
  byId("searchInput").addEventListener("input", (event) => {
    state.query = event.target.value;
    render();
  });

  byId("searchInput").addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.target.value = "";
      state.query = "";
      render();
      event.target.blur();
    }
  });

  byId("addTagForm").addEventListener("submit", (event) => {
    event.preventDefault();
    const input = byId("addTagInput");
    addTags(input.value);
    input.value = "";
  });

  byId("translateAllButton").addEventListener("click", handleTranslateAll);
  byId("translateSelectedButton").addEventListener("click", handleTranslateSelected);
  byId("selectVisibleButton").addEventListener("click", selectVisible);
  byId("clearSelectionButton").addEventListener("click", () => {
    state.selected.clear();
    render();
  });
  byId("resetButton").addEventListener("click", resetSample);
  byId("copyPromptButton").addEventListener("click", () => copyText(promptText()));
  byId("helpButton").addEventListener("click", () => showToast("原文用于生成；译文仅在你需要理解标签时显示。"));
  byId("moreButton").addEventListener("click", () => showToast("更多操作将在正式接入时连接到标签规则与缓存。"));

  document.addEventListener("keydown", (event) => {
    if (event.key === "/" && document.activeElement?.tagName !== "INPUT") {
      event.preventDefault();
      byId("searchInput").focus();
    }
    if (event.key === "Escape" && state.selected.size > 0 && document.activeElement?.tagName !== "INPUT") {
      state.selected.clear();
      render();
    }
  });

  document.addEventListener("click", (event) => {
    const layoutButton = event.target.closest("[data-layout]");
    if (layoutButton) {
      state.layout = layoutButton.dataset.layout;
      render();
      return;
    }

    const filterButton = event.target.closest("[data-filter]");
    if (filterButton) {
      state.filter = filterButton.dataset.filter;
      render();
      return;
    }

    const selectButton = event.target.closest("[data-select-tag]");
    if (selectButton) {
      toggleTagSelection(selectButton.dataset.selectTag);
      return;
    }

    const removeButton = event.target.closest("[data-remove-tag]");
    if (removeButton) {
      removeTag(removeButton.dataset.removeTag);
      return;
    }

    const inspectorButton = event.target.closest("[data-inspector-translate]");
    if (inspectorButton) {
      handleInspectorTranslate(inspectorButton.dataset.inspectorTranslate);
    }
  });
}

function init() {
  bindEvents();
  render();
}

document.addEventListener("DOMContentLoaded", init);
