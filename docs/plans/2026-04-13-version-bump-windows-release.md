# Version Bump Windows Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bump the app version from `0.9.2` to `0.9.3` and rebuild the Windows Release output so the updated build is clearly identifiable in the welcome dialog, about dialog, and exe metadata.

**Architecture:** Keep the existing version display code unchanged and update only the source-of-truth version in `pubspec.yaml`. Then run a fresh Windows release build so Flutter regenerates the executable metadata and asset bundle, and verify the resulting `build/windows/x64/runner/Release` directory reflects the new version and current source assets.

**Tech Stack:** Flutter, Dart, Windows runner resources, PowerShell

---

### Task 1: Bump the app version in source metadata

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Write the failing test**

This task is a metadata/configuration update, so use a direct file-state check instead of a unit test. First verify the source version is still the old value.

Run:

```bash
powershell -NoProfile -Command "(Get-Content 'C:\Users\admin\Downloads\NAI_NEW\pubspec.yaml') -match '^version:'"
```

Expected: output contains `version: 0.9.2`

**Step 2: Run check to verify the old state**

Run the same command and confirm it shows the old version.

Run:

```bash
powershell -NoProfile -Command "(Get-Content 'C:\Users\admin\Downloads\NAI_NEW\pubspec.yaml') -match '^version:'"
```

Expected: current state is `version: 0.9.2`

**Step 3: Write minimal implementation**

Update `pubspec.yaml`:

```yaml
version: 0.9.3
```

Do not change any other metadata.

**Step 4: Run check to verify the new state**

Run:

```bash
powershell -NoProfile -Command "(Get-Content 'C:\Users\admin\Downloads\NAI_NEW\pubspec.yaml') -match '^version:'"
```

Expected: output contains `version: 0.9.3`

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add pubspec.yaml
git commit -m "chore: bump app version to 0.9.3"
```

If `git status` reports this is not a repository, skip this step.

### Task 2: Rebuild the Windows Release output

**Files:**
- Refresh: `build/windows/x64/runner/Release`
- Reads from: `windows/runner/Runner.rc`

**Step 1: Write the failing test**

Before rebuilding, verify the existing release exe still reports the old version.

Run:

```bash
powershell -NoProfile -Command "(Get-Item 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\NAI_CasRand.exe').VersionInfo | Select-Object FileVersion,ProductVersion | Format-List"
```

Expected: both `FileVersion` and `ProductVersion` still read `0.9.2`

**Step 2: Run check to verify the stale build state**

Run the same command and confirm the build output has not yet been refreshed.

Run:

```bash
powershell -NoProfile -Command "(Get-Item 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\NAI_CasRand.exe').VersionInfo | Select-Object FileVersion,ProductVersion | Format-List"
```

Expected: old release exe still shows `0.9.2`

**Step 3: Write minimal implementation**

Run a fresh Windows release build from the project root:

```bash
flutter build windows --release
```

Do not manually edit `windows/runner/Runner.rc`; Flutter will propagate the version from `pubspec.yaml`.

**Step 4: Run check to verify the rebuilt state**

Run:

```bash
powershell -NoProfile -Command "(Get-Item 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\NAI_CasRand.exe').VersionInfo | Select-Object FileVersion,ProductVersion | Format-List"
```

Expected: both `FileVersion` and `ProductVersion` read `0.9.3`

Also verify the exe exists:

```bash
powershell -NoProfile -Command "Test-Path 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\NAI_CasRand.exe'"
```

Expected: `True`

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add pubspec.yaml
git commit -m "build: refresh windows release for 0.9.3"
```

If `git status` reports this is not a repository, skip this step.

### Task 3: Verify the rebuilt assets and user-facing update signal

**Files:**
- Verify: `build/windows/x64/runner/Release/data/flutter_assets/assets/l10n/en.json`
- Verify: `build/windows/x64/runner/Release/data/flutter_assets/assets/l10n/zh-CN.json`
- Verify indirectly via runtime metadata used by:
  - `lib/ui/navigation/widgets/navigation_view.dart`
  - `lib/ui/navigation/widgets/navigation_appbar.dart`

**Step 1: Write the failing test**

Before checking the rebuilt assets, define the exact verification target: the release asset bundle should reflect current source text, not stale copy.

Run:

```bash
powershell -NoProfile -Command "Select-String -Path 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\data\flutter_assets\assets\l10n\en.json' -Pattern 'comma-separated source acts as a grouped tag rule'"
```

Expected after a correct rebuild: one match line is printed

**Step 2: Run check to verify it now reflects the rebuilt output**

Run:

```bash
powershell -NoProfile -Command "Select-String -Path 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\data\flutter_assets\assets\l10n\en.json' -Pattern 'comma-separated source acts as a grouped tag rule'"
```

Expected: match found in the release asset bundle

Also verify the Chinese release asset:

```bash
powershell -NoProfile -Command "Select-String -Path 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\data\flutter_assets\assets\l10n\zh-CN.json' -Pattern '源文本使用逗号分隔时会作为一组提示词处理'"
```

Expected: match found in the release asset bundle

**Step 3: Write minimal implementation**

No further code change is expected here if Task 2 rebuilt correctly. This task is verification-only.

**Step 4: Run manual verification of the updated version signal**

Run the rebuilt app:

```bash
"build\windows\x64\runner\Release\NAI_CasRand.exe"
```

Manual checklist:

- welcome dialog shows version `0.9.3`
- about dialog shows version `0.9.3`
- replacement rules hint shows the grouped-source wording

If the welcome dialog does not appear because the stored `welcomeMessageVersion` already matches, clear it from settings or use the debug reset path before rechecking.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add pubspec.yaml
git commit -m "chore: verify windows release 0.9.3"
```

If `git status` reports this is not a repository, skip this step.

### Task 4: Final release verification for handoff

**Files:**
- Verify: `build/windows/x64/runner/Release`

**Step 1: Run final metadata verification**

Run:

```bash
powershell -NoProfile -Command "(Get-Item 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\NAI_CasRand.exe').VersionInfo | Select-Object FileVersion,ProductVersion | Format-List"
```

Expected: both values are `0.9.3`

**Step 2: Run final file-presence verification**

Run:

```bash
powershell -NoProfile -Command "Get-ChildItem 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release' | Select-Object Name"
```

Expected: output includes `NAI_CasRand.exe`, `data`, `flutter_windows.dll`, and plugin dlls

**Step 3: Prepare user handoff note**

Document the exact directory the user should run:

- `build/windows/x64/runner/Release/NAI_CasRand.exe`

And remind them the whole `Release` directory must stay together.

**Step 4: Commit**

If this workspace is a git repository:

```bash
git add pubspec.yaml
git commit -m "build: prepare windows release handoff"
```

If `git status` reports this is not a repository, skip this step.
