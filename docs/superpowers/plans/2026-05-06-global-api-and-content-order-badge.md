# Global API And Content Order Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the NovelAI API key behave as a global local setting and show selected `内容` prompt order indexes on homepage generation cards.

**Architecture:** Keep the existing config file format, but preserve the current in-memory API key whenever configs are loaded or imported. Track `内容` prompt selection indexes during prompt generation and pass the resulting badge text through `PayloadGenerationResult` into `InfoCardContent`, where the homepage card can render it.

**Tech Stack:** Flutter, Dart, Hive-backed local config storage, Flutter widget/unit tests

---

### Task 1: Lock down global API preservation behavior

**Files:**
- Modify: `test/ui/settings_page/settings_page_viewmodel_test.dart`
- Modify: `test/data/models/payload_config_prompt_replace_rules_test.dart`

- [ ] **Step 1: Write failing tests for preserving the current API key**

Add tests that:
- build a `PayloadConfig` whose current `settings.apiKey` is `current-key`
- load JSON whose `settings.api_key` is `imported-key`
- expect the resulting in-memory config to still use `current-key`

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:
```bash
flutter test test/ui/settings_page/settings_page_viewmodel_test.dart test/data/models/payload_config_prompt_replace_rules_test.dart
```

Expected:
- At least one new assertion fails because current code overwrites `settings.apiKey`

- [ ] **Step 3: Implement the minimal API-preservation behavior**

Change config loading code so callers can preserve the current API key while loading the rest of the config JSON.

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run:
```bash
flutter test test/ui/settings_page/settings_page_viewmodel_test.dart test/data/models/payload_config_prompt_replace_rules_test.dart
```

Expected:
- PASS

### Task 2: Lock down `内容` selection metadata

**Files:**
- Modify: `test/data/use_cases/generate_payload_use_case_character_placeholder_test.dart`
- Modify: `test/ui/generation_page/view_models/generation_page_viewmodel_test.dart`

- [ ] **Step 1: Write failing tests for content-order tracking**

Add tests that:
- build a root prompt config containing a `内容` prompt group
- verify single selection returns `1`
- verify multi-selection returns `1,3`-style output
- verify no `内容` selection returns no badge text

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:
```bash
flutter test test/data/use_cases/generate_payload_use_case_character_placeholder_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart
```

Expected:
- FAIL because `PayloadGenerationResult` and `InfoCardContent` do not yet carry the badge data

- [ ] **Step 3: Implement prompt metadata propagation and homepage rendering**

Make the prompt generation layer record selected `内容` string indexes, add the badge text to generation results and cards, and render the text on homepage cards.

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run:
```bash
flutter test test/data/use_cases/generate_payload_use_case_character_placeholder_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart
```

Expected:
- PASS

### Task 3: Regression verification

**Files:**
- No code changes expected

- [ ] **Step 1: Run the combined relevant test set**

Run:
```bash
flutter test test/ui/settings_page/settings_page_viewmodel_test.dart test/data/models/payload_config_prompt_replace_rules_test.dart test/data/use_cases/generate_payload_use_case_character_placeholder_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart
```

Expected:
- PASS

- [ ] **Step 2: Sanity-check formatting and analyzer-facing compile risks**

Run:
```bash
flutter test test/data/models/settings_batch_interval_jitter_test.dart
```

Expected:
- PASS
