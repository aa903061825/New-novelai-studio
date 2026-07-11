# Role Replacement Card Collapse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-card collapse and expand behavior to Script Workbench role replacement cards.

**Architecture:** Keep collapse state inside `_RoleReplacementCard` as local widget state. The view model and `RecastMapping` remain unchanged because this is presentation-only state.

**Tech Stack:** Flutter, `flutter_test`, existing Script page widgets.

## Global Constraints

- Do not call project API-backed translation, extraction, or cache generation tools.
- Do not write collapse state into script cache or workspace data.
- Preserve existing expanded-card behavior by default.

---

### Task 1: Role Replacement Card Collapse

**Files:**
- Modify: `test/ui/studio_script/studio_script_page_test.dart`
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`

**Interfaces:**
- Consumes: `_RoleReplacementCard.item.rules`, `_replacementRuleHasResult`, existing `StudioIconButton`.
- Produces: `_RoleReplacementCard` with local `_collapsed` state and keys `role-replacement-collapse-<sourceRoleId>` and `role-replacement-expand-<sourceRoleId>`.

- [ ] **Step 1: Write the failing widget test**

Add a test that builds a script page with one role replacement rule, verifies `role-replacement-reset-slot-0` is visible, taps `role-replacement-collapse-slot-0`, verifies `role-replacement-reset-slot-0` is hidden and `role-replacement-collapsed-summary-slot-0` is visible, then taps `role-replacement-expand-slot-0` and verifies the reset button returns.

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "role replacement cards can collapse and expand"
```

Expected: FAIL because the collapse button key does not exist yet.

- [ ] **Step 3: Implement the card state**

Convert `_RoleReplacementCard` from `StatelessWidget` to `StatefulWidget`. Add `bool _collapsed = false`, route all existing constructor fields through `widget`, and render a compact summary when `_collapsed` is true.

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "role replacement cards can collapse and expand"
```

Expected: PASS.

- [ ] **Step 5: Run a nearby regression slice**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "role replacement"
```

Expected: PASS for role replacement widget coverage.
