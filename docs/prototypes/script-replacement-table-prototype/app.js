const roleCards = {
  lily: {
    name: "莉莉",
    tags: ["lily", "silver hair", "blue eyes", "small horns"],
  },
};

const blocks = [
  {
    id: "bIdentity",
    scope: "character",
    location: "slot-0",
    kind: "tag",
    sourceText: "alice (wonder story)",
    terms: [
      {
        id: "tIdentity",
        text: "alice (wonder story)",
        category: "identity",
        frames: [1, 2, 3, 4, 5, 6, 7, 8, 9],
      },
    ],
  },
  {
    id: "bHair",
    scope: "character",
    location: "slot-0",
    kind: "tag",
    sourceText: "brown hair",
    terms: [
      {
        id: "tHair",
        text: "brown hair",
        category: "body",
        frames: [1, 2, 3, 4, 5, 6, 7, 8, 9],
      },
    ],
  },
  {
    id: "bOutfitPhrase",
    scope: "character",
    location: "slot-0",
    kind: "phrase",
    sourceText: "wearing a red jacket and black skirt",
    terms: [
      {
        id: "tJacket",
        text: "red jacket",
        category: "clothing",
        frames: [1, 2, 3, 4, 5, 8, 9],
      },
      {
        id: "tSkirt",
        text: "black skirt",
        category: "clothing",
        frames: [1, 2, 3, 4, 5, 8, 9],
      },
    ],
  },
  {
    id: "bWetPhrase",
    scope: "character",
    location: "slot-0",
    kind: "phrase",
    sourceText: "her shirt is wet",
    terms: [
      {
        id: "tWetShirt",
        text: "wet shirt",
        category: "state",
        frames: [4, 5],
      },
    ],
  },
  {
    id: "bAccessory",
    scope: "character",
    location: "slot-0",
    kind: "tag",
    sourceText: "round glasses",
    terms: [
      {
        id: "tGlasses",
        text: "round glasses",
        category: "accessory",
        frames: [1, 2, 3, 4, 5, 6],
      },
    ],
  },
  {
    id: "bSceneRain",
    scope: "scene",
    location: "base prompt",
    kind: "phrase",
    sourceText: "in a rainy city street at night",
    terms: [
      {
        id: "tRainyStreet",
        text: "rainy city street",
        category: "scene",
        frames: [1, 2, 3, 4],
      },
      {
        id: "tNight",
        text: "night",
        category: "scene",
        frames: [1, 2, 3, 4],
      },
    ],
  },
  {
    id: "bSceneWindow",
    scope: "scene",
    location: "base prompt",
    kind: "tag",
    sourceText: "broken shop window",
    terms: [
      {
        id: "tWindow",
        text: "broken shop window",
        category: "scene",
        frames: [2, 3],
      },
    ],
  },
  {
    id: "bSceneLight",
    scope: "scene",
    location: "base prompt",
    kind: "tag",
    sourceText: "warm indoor light",
    terms: [
      {
        id: "tWarmLight",
        text: "warm indoor light",
        category: "scene",
        frames: [6, 7, 8],
      },
    ],
  },
];

const categoryLabels = {
  identity: "身份",
  body: "外观",
  clothing: "服装",
  state: "服装状态",
  accessory: "饰品",
  scene: "场景",
};

const scopeLabels = {
  character: "角色",
  scene: "场景",
};

const modeLabels = {
  any: "任一出现",
  all: "同时出现",
  anchor: "锚点触发",
};

const compareRows = document.querySelector("#compareRows");
const identityDrop = document.querySelector("#identityDrop");
const identityTags = document.querySelector("#identityTags");
const bulkSummary = document.querySelector("#bulkSummary");
const simulationLog = document.querySelector("#simulationLog");
const searchInput = document.querySelector("#searchInput");

let nextMergeIndex = 1;
let state = createInitialState();

function createInitialState() {
  return {
    filterScope: "all",
    search: "",
    activeRowId: "row_bIdentity",
    identityTags: [],
    rows: blocks.map((block) => ({
      id: `row_${block.id}`,
      sourceBlockIds: [block.id],
      termIds: block.terms.map((term) => term.id),
      excludedTermIds: [],
      selected: false,
      action: "none",
      targetText: "",
      matchMode: "any",
      manualPhrase: "",
      merged: false,
    })),
  };
}

function render() {
  renderIdentityTags();
  renderRows();
  renderBulkSummary();
}

function renderIdentityTags() {
  if (state.identityTags.length === 0) {
    identityTags.innerHTML = '<span class="hint">未选择目标角色</span>';
    return;
  }

  identityTags.innerHTML = state.identityTags
    .map((tag) => `<span class="chip">${escapeHtml(tag)}</span>`)
    .join("");
}

function renderRows() {
  const visibleRows = state.rows.filter(rowPassesFilters);

  if (visibleRows.length === 0) {
    compareRows.innerHTML =
      '<div class="empty-state">没有匹配的源词。换个搜索词或切回“全部”。</div>';
    return;
  }

  compareRows.innerHTML = visibleRows.map(renderRow).join("");
}

function renderRow(row) {
  const includedTerms = getIncludedTerms(row);
  const rowBlocks = getRowBlocks(row);
  const scopes = unique(rowBlocks.map((block) => block.scope));
  const categories = unique(includedTerms.map((term) => term.category));
  const frames = framesForRow(row);
  const hasPhrase = rowBlocks.some((block) => block.kind === "phrase");
  const partialPhrase = hasPartialPhrase(row);
  const sourceNote = rowBlocks
    .filter((block) => block.kind === "phrase")
    .map((block) => block.sourceText)
    .join(" / ");
  const selectedClass = row.selected ? " is-selected" : "";
  const activeClass = row.id === state.activeRowId ? " is-active" : "";
  const mergedClass = row.merged ? " is-merged" : "";
  const deleteClass = row.action === "delete" ? " is-delete" : "";
  const targetDisabled = row.action === "delete" ? "disabled" : "";
  const targetPlaceholder =
    row.action === "delete" ? "此行会删除源词" : "留空 = 不替换；填入后才替换";

  return `
    <article class="compare-row${selectedClass}${activeClass}${mergedClass}" data-row-id="${escapeAttr(
      row.id,
    )}">
      <input class="row-select" data-row-select="${escapeAttr(row.id)}" type="checkbox" ${
        row.selected ? "checked" : ""
      } aria-label="选择此替换行" />
      <div class="source-cell">
        <div class="source-title">
          <strong>${row.merged ? "合并源词" : "源提示词"}</strong>
          <span class="badge ${escapeAttr(scopes[0] ?? "character")}">${escapeHtml(
            scopes.map((scope) => scopeLabels[scope]).join(" + "),
          )}</span>
        </div>
        <div class="source-chips">
          ${renderSourceChips(row)}
        </div>
        ${
          sourceNote
            ? `<p class="source-note">来源片段：${escapeHtml(sourceNote)}</p>`
            : ""
        }
        <div class="row-meta">
          <span class="badge">帧 ${escapeHtml(formatFrames(frames))}</span>
          <span class="badge">${escapeHtml(
            unique(rowBlocks.map((block) => block.location)).join(" / "),
          )}</span>
          ${categories
            .map(
              (category) =>
                `<span class="badge">${escapeHtml(categoryLabels[category])}</span>`,
            )
            .join("")}
          ${row.merged ? '<span class="badge warning">手动合并</span>' : ""}
        </div>
      </div>
      <div class="arrow-cell">
        <button class="arrow-button" data-copy-row="${escapeAttr(
          row.id,
        )}" type="button" title="把源词复制到右侧">→</button>
      </div>
      <div class="replace-cell${deleteClass}">
        <div class="replace-title">
          <strong>${replacementTitle(row)}</strong>
          <div class="replace-actions">
            <button class="icon-button is-danger" data-delete-row="${escapeAttr(
              row.id,
            )}" type="button" title="删除源词">删</button>
            <button class="icon-button" data-reset-row="${escapeAttr(
              row.id,
            )}" type="button" title="恢复默认">回</button>
          </div>
        </div>
        <input class="target-input" data-target-input="${escapeAttr(
          row.id,
        )}" value="${escapeAttr(row.targetText)}" placeholder="${escapeAttr(
          targetPlaceholder,
        )}" ${targetDisabled} />
        <div class="mode-row" aria-label="匹配模式">
          ${Object.entries(modeLabels)
            .map(
              ([mode, label]) =>
                `<button class="mode-button ${
                  row.matchMode === mode ? "is-active" : ""
                }" data-mode-row="${escapeAttr(row.id)}" data-mode="${escapeAttr(
                  mode,
                )}" type="button">${escapeHtml(label)}</button>`,
            )
            .join("")}
        </div>
        ${
          partialPhrase
            ? `<div class="phrase-warning">
                <span>自然语言片段只处理了其中一部分词。更稳的做法是合并整句，或在这里写一个手动片段覆盖。</span>
                <textarea class="manual-phrase" data-manual-phrase="${escapeAttr(
                  row.id,
                )}" placeholder="可选：整句替换片段">${escapeHtml(
                  row.manualPhrase,
                )}</textarea>
              </div>`
            : hasPhrase
              ? `<textarea class="manual-phrase" data-manual-phrase="${escapeAttr(
                  row.id,
                )}" placeholder="可选：自然语言整句覆盖">${escapeHtml(
                  row.manualPhrase,
                )}</textarea>`
              : ""
        }
        <p class="replace-hint">${escapeHtml(replacementHint(row))}</p>
      </div>
    </article>
  `;
}

function renderSourceChips(row) {
  return row.termIds
    .map((termId) => {
      const term = getTerm(termId);
      const excluded = row.excludedTermIds.includes(termId);
      const excludedClass = excluded ? " is-excluded" : "";

      return `<button class="source-chip ${escapeAttr(
        term.category,
      )}${excludedClass}" data-toggle-term="${escapeAttr(
        row.id,
      )}" data-term-id="${escapeAttr(term.id)}" type="button" title="点击可取消/恢复这个源词">${escapeHtml(
        term.text,
      )}</button>`;
    })
    .join("");
}

function replacementTitle(row) {
  if (row.action === "delete") return "删除源词";
  if (row.targetText.trim() || row.manualPhrase.trim()) return "替换输出";
  return "保持原样";
}

function replacementHint(row) {
  if (row.action === "delete") return "只有显式点“删”才会删除；空目标不会删除。";
  if (row.targetText.trim()) {
    return `会在 ${formatFrames(framesForRow(row))} 帧，把左侧源词替换为右侧目标。`;
  }
  if (row.manualPhrase.trim()) {
    return "手动片段会覆盖这条自然语言来源的替换文本。";
  }
  return "默认不替换。需要变化时，在右侧填目标、点删除，或先合并源词。";
}

function renderBulkSummary() {
  const count = state.rows.filter((row) => row.selected).length;
  bulkSummary.textContent = count > 0 ? `已选中 ${count} 行` : "没有选中行";
}

function rowPassesFilters(row) {
  const rowBlocks = getRowBlocks(row);
  const scopes = unique(rowBlocks.map((block) => block.scope));
  if (state.filterScope !== "all" && !scopes.includes(state.filterScope)) {
    return false;
  }

  const query = state.search.trim().toLowerCase();
  if (!query) return true;

  const terms = row.termIds.map((id) => getTerm(id));
  const haystack = [
    ...terms.map((term) => term.text),
    ...terms.map((term) => categoryLabels[term.category]),
    ...rowBlocks.map((block) => block.sourceText),
    ...rowBlocks.map((block) => scopeLabels[block.scope]),
  ]
    .join(" ")
    .toLowerCase();

  return haystack.includes(query);
}

function getRowBlocks(row) {
  return row.sourceBlockIds.map((id) => blocks.find((block) => block.id === id));
}

function getTerm(termId) {
  for (const block of blocks) {
    const term = block.terms.find((item) => item.id === termId);
    if (term) return term;
  }
  throw new Error(`Unknown term id: ${termId}`);
}

function getIncludedTerms(row) {
  return row.termIds
    .filter((termId) => !row.excludedTermIds.includes(termId))
    .map(getTerm);
}

function framesForRow(row) {
  const termFrames = getIncludedTerms(row).map((term) => term.frames);
  if (termFrames.length === 0) return [];
  if (row.matchMode === "anchor") return termFrames[0];
  if (row.matchMode === "all") return intersectFrames(termFrames);
  return unique(termFrames.flat()).sort((a, b) => a - b);
}

function hasPartialPhrase(row) {
  if (row.action === "none" && !row.targetText.trim() && !row.manualPhrase.trim()) {
    return false;
  }

  return getRowBlocks(row).some((block) => {
    if (block.kind !== "phrase" || block.terms.length < 2) return false;
    const includedCount = block.terms.filter(
      (term) =>
        row.termIds.includes(term.id) && !row.excludedTermIds.includes(term.id),
    ).length;
    return includedCount > 0 && includedCount < block.terms.length;
  });
}

function intersectFrames(frameLists) {
  const [first, ...rest] = frameLists.map((frames) => new Set(frames));
  return [...first]
    .filter((frame) => rest.every((frames) => frames.has(frame)))
    .sort((a, b) => a - b);
}

function formatFrames(frames) {
  if (frames.length === 0) return "无匹配";

  const ranges = [];
  let start = frames[0];
  let previous = frames[0];

  for (let index = 1; index <= frames.length; index += 1) {
    const current = frames[index];
    if (current === previous + 1) {
      previous = current;
      continue;
    }

    ranges.push(start === previous ? `${start}` : `${start}-${previous}`);
    start = current;
    previous = current;
  }

  return ranges.join(", ");
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function setActiveRow(rowId) {
  state.activeRowId = rowId;
}

function updateRow(rowId, updater) {
  const row = state.rows.find((item) => item.id === rowId);
  if (!row) return;
  updater(row);
}

function applyRoleCard(cardId) {
  const role = roleCards[cardId];
  if (!role) return;
  state.identityTags = [...role.tags];
  render();
}

function quickFillActiveRow(value) {
  updateRow(state.activeRowId, (row) => {
    row.action = "replace";
    row.targetText = value;
  });
  render();
}

function mergeSelectedRows() {
  const selectedRows = state.rows.filter((row) => row.selected);
  if (selectedRows.length < 2) return;

  const mergedRow = {
    id: `row_merge_${nextMergeIndex}`,
    sourceBlockIds: unique(selectedRows.flatMap((row) => row.sourceBlockIds)),
    termIds: unique(selectedRows.flatMap((row) => row.termIds)),
    excludedTermIds: unique(selectedRows.flatMap((row) => row.excludedTermIds)),
    selected: false,
    action: "none",
    targetText: "",
    matchMode: "any",
    manualPhrase: "",
    merged: true,
  };
  nextMergeIndex += 1;

  const selectedIds = new Set(selectedRows.map((row) => row.id));
  const insertionIndex = state.rows.findIndex((row) => selectedIds.has(row.id));
  state.rows = state.rows.filter((row) => !selectedIds.has(row.id));
  state.rows.splice(insertionIndex, 0, mergedRow);
  state.activeRowId = mergedRow.id;
  render();
}

function simulate() {
  const activeRules = state.rows.filter(
    (row) =>
      row.action === "delete" || row.targetText.trim() || row.manualPhrase.trim(),
  );

  if (activeRules.length === 0 && state.identityTags.length === 0) {
    simulationLog.innerHTML =
      "<p>当前仍然是原样输出：没有身份目标，也没有替换或删除规则。</p>";
    return;
  }

  const identityLine =
    state.identityTags.length > 0
      ? `<p><strong>目标身份：</strong>${escapeHtml(state.identityTags.join(", "))}</p>`
      : "<p><strong>目标身份：</strong>未设置</p>";

  const ruleLines = activeRules.map((row) => {
    const source = getIncludedTerms(row)
      .map((term) => term.text)
      .join(" + ");
    const frames = formatFrames(framesForRow(row));
    const mode = modeLabels[row.matchMode];
    const target =
      row.action === "delete"
        ? "删除"
        : row.manualPhrase.trim() || row.targetText.trim();

    return `<p><strong>${escapeHtml(source)}</strong> → ${escapeHtml(
      target,
    )} <span class="badge">${escapeHtml(mode)}</span> <span class="badge">帧 ${escapeHtml(
      frames,
    )}</span></p>`;
  });

  simulationLog.innerHTML = [identityLine, ...ruleLines].join("");
}

compareRows.addEventListener("click", (event) => {
  const rowElement = event.target.closest(".compare-row");
  if (rowElement) {
    setActiveRow(rowElement.dataset.rowId);
  }

  const chip = event.target.closest("[data-toggle-term]");
  if (chip) {
    const rowId = chip.dataset.toggleTerm;
    const termId = chip.dataset.termId;
    updateRow(rowId, (row) => {
      const isExcluded = row.excludedTermIds.includes(termId);
      if (!isExcluded && getIncludedTerms(row).length <= 1) return;
      row.excludedTermIds = isExcluded
        ? row.excludedTermIds.filter((id) => id !== termId)
        : [...row.excludedTermIds, termId];
    });
    render();
    return;
  }

  const copyButton = event.target.closest("[data-copy-row]");
  if (copyButton) {
    const rowId = copyButton.dataset.copyRow;
    updateRow(rowId, (row) => {
      row.action = "replace";
      row.targetText = getIncludedTerms(row)
        .map((term) => term.text)
        .join(", ");
    });
    render();
    return;
  }

  const deleteButton = event.target.closest("[data-delete-row]");
  if (deleteButton) {
    updateRow(deleteButton.dataset.deleteRow, (row) => {
      row.action = "delete";
    });
    render();
    return;
  }

  const resetButton = event.target.closest("[data-reset-row]");
  if (resetButton) {
    updateRow(resetButton.dataset.resetRow, (row) => {
      row.action = "none";
      row.targetText = "";
      row.manualPhrase = "";
      row.excludedTermIds = [];
      row.matchMode = "any";
    });
    render();
    return;
  }

  const modeButton = event.target.closest("[data-mode-row]");
  if (modeButton) {
    updateRow(modeButton.dataset.modeRow, (row) => {
      row.matchMode = modeButton.dataset.mode;
    });
    render();
  }
});

compareRows.addEventListener("change", (event) => {
  const selector = event.target.closest("[data-row-select]");
  if (!selector) return;

  updateRow(selector.dataset.rowSelect, (row) => {
    row.selected = selector.checked;
  });
  renderBulkSummary();
});

compareRows.addEventListener("input", (event) => {
  const targetInput = event.target.closest("[data-target-input]");
  if (targetInput) {
    updateRow(targetInput.dataset.targetInput, (row) => {
      row.targetText = targetInput.value;
      if (targetInput.value.trim()) row.action = "replace";
      if (!targetInput.value.trim() && row.action === "replace") row.action = "none";
    });
    return;
  }

  const manualPhrase = event.target.closest("[data-manual-phrase]");
  if (manualPhrase) {
    updateRow(manualPhrase.dataset.manualPhrase, (row) => {
      row.manualPhrase = manualPhrase.value;
    });
  }
});

compareRows.addEventListener("blur", (event) => {
  if (
    event.target.matches("[data-target-input]") ||
    event.target.matches("[data-manual-phrase]")
  ) {
    render();
  }
}, true);

document.querySelectorAll(".filter-tab").forEach((button) => {
  button.addEventListener("click", () => {
    document
      .querySelectorAll(".filter-tab")
      .forEach((item) => item.classList.remove("is-active"));
    button.classList.add("is-active");
    state.filterScope = button.dataset.scope;
    renderRows();
  });
});

searchInput.addEventListener("input", () => {
  state.search = searchInput.value;
  renderRows();
});

document.querySelector("#resetButton").addEventListener("click", () => {
  nextMergeIndex = 1;
  state = createInitialState();
  searchInput.value = "";
  document
    .querySelectorAll(".filter-tab")
    .forEach((item) => item.classList.toggle("is-active", item.dataset.scope === "all"));
  simulationLog.innerHTML =
    "<p>默认没有任何输出变化。填目标、删除、或合并后再点“应用模拟”。</p>";
  render();
});

document.querySelector("#mergeRowsButton").addEventListener("click", mergeSelectedRows);
document.querySelector("#clearSelectionButton").addEventListener("click", () => {
  state.rows.forEach((row) => {
    row.selected = false;
  });
  render();
});
document.querySelector("#simulateButton").addEventListener("click", simulate);

document.querySelectorAll(".role-card").forEach((card) => {
  card.addEventListener("click", () => applyRoleCard(card.dataset.cardId));
  card.addEventListener("dragstart", (event) => {
    event.dataTransfer.setData("text/plain", card.dataset.cardId);
  });
});

document.querySelectorAll(".quick-fill").forEach((card) => {
  card.addEventListener("click", () => quickFillActiveRow(card.dataset.fill));
});

identityDrop.addEventListener("dragover", (event) => {
  event.preventDefault();
  identityDrop.classList.add("is-over");
});
identityDrop.addEventListener("dragleave", () => {
  identityDrop.classList.remove("is-over");
});
identityDrop.addEventListener("drop", (event) => {
  event.preventDefault();
  identityDrop.classList.remove("is-over");
  applyRoleCard(event.dataTransfer.getData("text/plain"));
});

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttr(value) {
  return escapeHtml(value);
}

render();
