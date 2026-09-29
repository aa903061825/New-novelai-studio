# Prompt Atlas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dependency-free local HTML viewer for the 18 images in `C:\Users\admin\Downloads\新建文件夹 (3)` with clickable image cards, readable bilingual prompt chips, model metadata, and positive/negative prompt views.

**Architecture:** A one-off offline extraction pass reads only the root-level image metadata and produces canonical records in memory. The final deliverable is one self-contained `提示词查看器.html` containing relative image paths, escaped JSON data, CSS, and vanilla JavaScript; no project API, server, external asset, or extra JSON file is required at runtime.

**Tech Stack:** Native HTML/CSS/JavaScript, inline JSON, Python 3 standard library for read-only PNG/JPEG metadata extraction during the build, browser smoke test with a local file URL.

---

### Task 1: Inventory root-level images and extract canonical metadata

**Files:**
- Read: `/mnt/c/Users/admin/Downloads/新建文件夹 (3)/*.{png,jpg,jpeg,webp,avif}`
- Create: none; keep the extraction pass in memory/terminal output

- [ ] **Step 1: Enumerate only the approved scope**

Run a read-only file listing and assert that the root-level image count is 18; do not recurse into `逍遥西游服务端源码`.

```bash
find '/mnt/c/Users/admin/Downloads/新建文件夹 (3)' -maxdepth 1 -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.avif' \) \
  -printf '%f\n' | sort
```

Expected: 18 filenames, including the two `.jpg` files and the `.png` whose magic bytes identify it as JPEG.

- [ ] **Step 2: Parse generator metadata without decoding pixels**

Use the Python standard library (`struct`, `zlib`, `json`) to read PNG `tEXt`/`iTXt` chunks and JPEG APP/COM segments. Convert every file into this exact record shape:

```js
{
  id: "stable filename",
  filename: "original filename",
  src: "./original filename",
  formatNote: "png | jpeg content with png extension | ...",
  positive: [{ raw: "...", translation: "...", category: "...", weight: 1, status: "translated|pending" }],
  negative: [{ raw: "...", translation: "...", category: "negative", weight: 1, status: "translated|pending" }],
  model: { base: "...", hash: "...", source: "...", components: ["..."] },
  params: { steps: null, sampler: "...", cfg: null, seed: null, size: "..." },
  metadataStatus: "complete|partial|missing|unparseable",
  metadataNote: "human-readable status"
}
```

Extract NovelAI `Comment.prompt`, `Comment.uc`, `model_name`, `model_hash`, and sampling fields; ComfyUI `prompt`/`workflow` text nodes and loader nodes; and `parameters` blocks. Treat missing or malformed fields as `null`/empty arrays rather than failing the batch.

- [ ] **Step 3: Confirm the extracted model summary**

Before embedding data, verify these known records from the metadata already inspected:

```text
0A1C...      rlskck.safetensors
3DFB...      oneObsessionAnima_v40.safetensors
Anima...     anima_baseV10.safetensors
CCC2...      miaomiaoRealskin_epsV13.safetensors
4D7B...      NovelAI Diffusion V5 / 0ADF9AB7
9714...      NovelAI Diffusion V5 / 0ADF9AB7
E033...      krea2TurboOfficialComfy_krea2TurboInt8.safetensors
```

Keep `3A6C...` as a visible record with an empty model field and keep images with no prompt metadata visible with `metadataStatus: "missing"`.

### Task 2: Prepare offline translation and tag normalization

**Files:**
- Modify: in-memory record data before HTML generation
- Create: none

- [ ] **Step 1: Split prompt text into display tags without destroying source syntax**

Normalize only for display. Preserve the original `raw` string. Split on commas and meaningful newlines, retain tokens such as `1.4::tag::`, `<lora:name:0.8>`, bracketed artist syntax, Chinese tags, and custom identifiers as single tags. Extract a numeric weight only when the syntax is unambiguous; otherwise keep `weight: 1` and the original text.

- [ ] **Step 2: Apply deterministic categories**

Use ordered keyword rules for `quality`, `character`, `appearance`, `clothing`, `pose`, `scene`, `style`, `negative`, and `other`. Negative records always use the negative color/status. Do not infer a character identity or invent a category when the token is a custom LoRA or artist name.

- [ ] **Step 3: Generate bilingual labels offline**

Use a local translation dictionary for common tags and the model's reasoning capacity for the extracted finite set. Store Chinese in `translation`, keep English/Chinese source tokens unchanged where appropriate, and set `status: "pending"` when a token is a proper name, LoRA identifier, artist tag, or otherwise uncertain. Never call any project/API credential or translation endpoint.

### Task 3: Build the self-contained HTML viewer

**Files:**
- Create: `/mnt/c/Users/admin/Downloads/新建文件夹 (3)/提示词查看器.html`

- [ ] **Step 1: Add document shell and embedded data**

Generate a UTF-8 document with `<meta name="viewport">`, Chinese page title, a non-networking inline `<style>`, and a `<script type="application/json" id="promptData">` containing the escaped canonical records. Use only relative image paths so the file works when double-clicked.

- [ ] **Step 2: Implement the thumbnail gallery**

Render one card per record with lazy-loaded image, filename, model summary, and a metadata badge (`有提示词`, `无提示词`, or `参数不完整`). Add a filename/model search field and keep card hit targets at least 44px high.

- [ ] **Step 3: Implement the detail view and readable chip wall**

Clicking a card opens a modal or side drawer with:

```text
image preview → filename/model/params → 正向提示词 → 负向提示词
```

Render every token as an independent chip. Each chip uses two readable lines: original token in a clear smaller monospace line, Chinese translation in a larger high-contrast line, with weight in the corner. Long chips wrap instead of truncating. Pending translations retain the raw token and show `待确认`.

- [ ] **Step 4: Add interaction and accessibility behavior**

Implement positive/negative tabs, category filters, search across filename/raw/Chinese text, `Esc` to close, close button with an accessible label, visible keyboard focus, and an empty state for records without prompt metadata. Do not add external fonts, icon libraries, analytics, or network calls.

### Task 4: Validate the final local artifact

**Files:**
- Read: `/mnt/c/Users/admin/Downloads/新建文件夹 (3)/提示词查看器.html`
- Verify: unchanged image files in `/mnt/c/Users/admin/Downloads/新建文件夹 (3)`

- [ ] **Step 1: Run static integrity checks**

Verify that the HTML exists, contains 18 image records, includes the expected model names, and contains no external `http://`/`https://` script, stylesheet, image, or fetch dependency.

```bash
test -s '/mnt/c/Users/admin/Downloads/新建文件夹 (3)/提示词查看器.html'
grep -F 'oneObsessionAnima_v40.safetensors' '/mnt/c/Users/admin/Downloads/新建文件夹 (3)/提示词查看器.html'
grep -F 'NovelAI Diffusion V5' '/mnt/c/Users/admin/Downloads/新建文件夹 (3)/提示词查看器.html'
grep -F '待确认' '/mnt/c/Users/admin/Downloads/新建文件夹 (3)/提示词查看器.html'
```

Expected: all checks succeed and the only image URLs are relative paths beginning with `./`.

- [ ] **Step 2: Browser smoke-test representative records**

Open the file via a browser and verify one ComfyUI image, one NovelAI image, one missing-metadata image, positive/negative switching, search by English and Chinese, modal close with `Esc`, and that Chinese text is visibly larger than the raw token while still inside compact independent chips.

- [ ] **Step 3: Check that source images remain unchanged**

Compare image modification times and hashes before/after generation for the 18 root-level images. The viewer build must not modify any image.

- [ ] **Step 4: Report the artifact and limitations**

Return a clickable local file link, mention that it is offline and read-only, and note any tags left as `待确认` or any images whose metadata was absent.
