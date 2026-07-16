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

<!-- project-context:begin -->
For non-trivial project-specific work, use an ephemeral goal brief and decide whether the on-demand project knowledge index at `.agents/skills/project-context` is needed. When it is needed, read `references/index.md` first and only load relevant references; keep them limited to current references. Never read project history unless the user explicitly asks to consult history. Never read `history/index.md` or history records unless the user explicitly asks to consult project history.
<!-- project-context:end -->

## Project Update Shortcut

When the user says "更新一下当前项目" or an equivalent instruction, treat it as a project maintenance request for this local repo:

- Inspect `git status --short --branch`, current branch, remotes, and version state before changing anything.
- Run `git fetch origin` first. If the current branch has a clear upstream, merge or fast-forward from that upstream. If the merge target is ambiguous, or the worktree has unrelated dirty changes that could be affected, stop and ask before merging, stashing, staging, or committing.
- Update the app version in `pubspec.yaml`; by default use the next patch version from the currently checked-out file unless the user specifies another version.
- Run the appropriate lightweight verification for the touched files, and report any skipped verification explicitly.
