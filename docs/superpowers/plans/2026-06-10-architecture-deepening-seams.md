# Architecture Deepening Seams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract small, tested domain seams from large UI/view-model surfaces so architectural improvements are useful immediately and safe to continue.

**Architecture:** Keep current screens and view models as adapters. Move rule parsing, grouping, deduplication, and serialization into a `FilterRuleDocument` domain object first. Then introduce a `ScriptAiRoleAssemblyApplication` seam around AI role-extraction materialization so that Script Recast behavior can be verified without pumping the full Studio Script page.

**Tech Stack:** Flutter/Dart, existing `PromptTagClassifier`, `PromptTagProcessor`, `WorkspacePaths`, `flutter_test`, Beads.

---

## Scope

In scope:

- Add a fast domain test target for filter-rule ordering and deduplication.
- Extract filter-rule document behavior from `FilterRulesLibraryDialog`.
- Preserve the existing widget behavior expected by batch-add tests.
- Start a Script Recast role-extraction application seam after the filter-rule slice is green.
- Keep Beads updated with the completed slice and follow-up architecture work.

Out of scope:

- Full decomposition of `studio_script_page.dart` or `studio_script_viewmodel.dart`.
- Redesigning the filter-rules UI.
- Changing prompt-tag classifier semantics.
- Broad localization cleanup of existing mojibake strings.

## File Structure

Create:

- `lib/ui/studio_core/services/filter_rule_document.dart`
- `test/ui/studio_core/filter_rule_document_test.dart`
- `lib/data/studio/services/script_ai_role_assembly_application.dart`
- `test/data/studio/services/script_ai_role_assembly_application_test.dart`

Modify:

- `lib/ui/studio_core/widgets/filter_rules_library_dialog.dart`
- `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`

## Task 1: Filter Rule Document

**Files:**

- Create: `lib/ui/studio_core/services/filter_rule_document.dart`
- Create: `test/ui/studio_core/filter_rule_document_test.dart`
- Modify: `lib/ui/studio_core/widgets/filter_rules_library_dialog.dart`

- [x] Step 1: Write failing domain tests for automatic batch-add ordering, duplicate removal, known-block overrides, and source-order block display.
- [x] Step 2: Implement `FilterRuleDocument` with parse, add-to-block, add-auto, flatten, and serialization APIs.
- [x] Step 3: Replace duplicated dialog helpers with the document APIs while keeping UI state shape small.
- [x] Step 4: Run the fast document test and the existing batch-add widget test.

## Task 2: Script AI Role Assembly Application

**Files:**

- Create: `lib/data/studio/services/script_ai_role_assembly_application.dart`
- Create: `test/data/studio/services/script_ai_role_assembly_application_test.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`

- [x] Step 1: Add a pure data test for applying an AI role extraction to recast mapping state.
- [x] Step 2: Move role-assembly merge/application policy out of the view model behind a narrow application service.
- [x] Step 3: Keep the view model as an adapter that prepares mapping state, labels AI stages, calls the application service, and publishes state.
- [x] Step 4: Run the new service test plus focused existing Script Recast service tests.

## Verification

- [x] `flutter test test/ui/studio_core/filter_rule_document_test.dart`
- [x] `flutter test test/ui/studio_core/filter_rules_library_dialog_test.dart --plain-name "filter rule blocks can batch add tags"`
- [x] `flutter test test/data/studio/services/script_ai_role_assembly_application_test.dart`
- [x] `flutter analyze`
