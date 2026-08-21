# Codex Instructions


## Bug / Regression Root Cause Protocol

When the user reports something broken, empty, unexpected, regressed, flaky, or asks "why" something happened, treat it as a root-cause investigation by default.

- Use `superpowers:systematic-debugging` before implementing fixes; if that skill is unavailable, still follow the root-cause investigation rules below.
- Do not stop at a UI fallback, null guard, retry, or compatibility patch unless the upstream mechanism has been identified or the remaining uncertainty is stated clearly.
- Separate symptom relief from root-cause repair in updates and final answers.
- Before changing code, identify the failing mechanism: the data shape, lifecycle step, state transition, stale cache, filtering rule, merge rule, permission boundary, or invariant that produced the visible symptom.
- Add or run a regression test that would fail for the mechanism, not only for the visible UI state.
- If a fallback is still needed for old data, keep it as a compatibility layer and also fix the shared path that creates new bad data.

## Script / Translation Cache API Ban

When modifying scripts, building or repairing Script Recast caches, translating
cache display names, or filling translation cache entries, never use the user's
configured API, OpenAI-compatible endpoint, NAI token, proxy, or any
project-stored credential.

- Use Codex's own reasoning/model capacity plus local repository files, cache
  JSON, source frame prompts, and user-provided instructions instead.
- Do not run project tools or scripts that would trigger API-backed translation,
  extraction, or cache generation unless the user explicitly grants a one-time
  exception in the current chat.
- Treat this as a hard project rule for "改剧本", "剧本缓存", "翻译缓存", and
  related Script Recast work.

## Missing Target Character Appearance Evidence

- When a target character card lacks a stable hairstyle or other appearance tag
  needed for Script Recast replacement, the user authorizes a read-only search
  on `https://danbooru.donmai.us/` for the missing evidence.
- Record the exact Danbooru character/variant tag, post ids, and source tags.
  Separate character-level stable traits from outfit/skin-specific traits; do
  not promote one skin's hairstyle to the character-level default.
- Prefer official-art/default-form posts for character-level evidence. Back up
  the active character library before filling it, keep the source script root
  read-only, and do not use any project/user API or credential for the lookup.

## Default Script Recast Source Scope

- Treat `E:\NAI的脚本群\作品集\带图精品` as the default source root for the
  user's scripts.
- When the user says scripts were added or asks to update Script Recast caches
  without naming another source path, inspect this root and update caches only
  for new or changed scripts contained under it.
- Do not scan or process scripts from any other source root unless the user
  explicitly names or authorizes that root in the current chat.
- Keep the source root read-only during cache work. This source-scope rule does
  not change the active application cache output directory.

<!-- project-context:begin -->
For non-trivial project-specific work, use an ephemeral goal brief and decide whether the on-demand project knowledge index at `.agents/skills/project-context` is useful. When current knowledge is useful, read `references/index.md` first and only load relevant references. Codex decides when project history is relevant; when it is useful, start at `history/index.md` and load the history needed for the task.
<!-- project-context:end -->

## Project Update Shortcut

When the user says "更新一下当前项目" or an equivalent instruction, treat it as a project maintenance request for this local repo:

- Inspect `git status --short --branch`, current branch, remotes, and version state before changing anything.
- Run `git fetch origin` first. If the current branch has a clear upstream, merge or fast-forward from that upstream. If the merge target is ambiguous, or the worktree has unrelated dirty changes that could be affected, stop and ask before merging, stashing, staging, or committing.
- Update the app version in `pubspec.yaml`; by default use the next patch version from the currently checked-out file unless the user specifies another version.
- Run the appropriate lightweight verification for the touched files, and report any skipped verification explicitly.
- After source synchronization and the version update, build the current Windows Release application with `flutter build windows --release`; the local update is not complete until the runnable Release package contains the new code.
- Before the build, record its start time. After a successful build, verify that both `build/windows/x64/runner/Release/Novel_Studio.exe` and `build/windows/x64/runner/Release/data/app.so` exist and have fresh `LastWriteTime` values at or after that build start time. Report both absolute artifact paths and timestamps.
- If `Novel_Studio.exe` is already running, never terminate or restart it automatically. First tell the user to save their work and obtain explicit confirmation; only after confirmation may the old process be terminated and the new Release build launched. Without confirmation, leave the existing process untouched and report the built artifact paths instead.

## NAI / Vibe Experiment Reporting

For NAI image-generation, Vibe encoding, Vibe ablation, or visual comparison
experiments, use a local preview webpage as the primary user-facing report unless
the user explicitly requests another format.

- Follow the visual-audit pattern established by
  `.codex-runtime/qaq1-multilight-material-r1/preview/`: stage navigation,
  unambiguous Chinese member/variant labels, fixed comparison ordering and
  colors, full contact sheets, original-pixel crops, and a per-image browser.
- Every raw image entry must expose its exact source or provenance, positive and
  negative prompts, model, dimensions, seed, sampler, steps, Scale, CFG rescale,
  IE, Strength, payload hash, and PNG Comment verification when available.
- Make root-cause repair, symptom relief, partial evidence, failure, and package
  eligibility visually distinct. Never present a research-only Vibe as a formal
  candidate.
- Keep the preview local and read-only by default. Do not publish it or modify a
  formal Vibe package unless the user separately authorizes that action.
- Use chat updates for concise conclusions and a link to the preview; do not make
  the user infer variant identity from filenames or prose alone.
