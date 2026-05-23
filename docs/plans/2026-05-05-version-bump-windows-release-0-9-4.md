# Version Bump Windows Release 0.9.4 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bump the app version from `0.9.3` to `0.9.4` and rebuild the Windows Release output so the exe metadata, splash/welcome version, and about dialog all reflect `0.9.4`.

**Architecture:** Keep the existing version display code unchanged because both the welcome dialog and the about dialog already read `packageInfo.version`. Update only the source-of-truth version in `pubspec.yaml`, rebuild Windows Release, then verify the rebuilt app metadata and user-visible version signals.

**Tech Stack:** Flutter, Dart, Windows runner build pipeline, PowerShell

---

### Task 1: Bump the app source version to 0.9.4

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Write the failing test**

This is a metadata update, so first verify the old version is still present.

Run:

```bash
powershell -NoProfile -Command "(Get-Content 'C:\Users\admin\Downloads\NAI_NEW\pubspec.yaml') -match '^version:'"
```

Expected: output contains `version: 0.9.3`

**Step 2: Run check to verify old state**

Run the same command again and confirm the current source version is still `0.9.3`.

**Step 3: Write minimal implementation**

Update `pubspec.yaml` to:

```yaml
version: 0.9.4
```

Do not change any other metadata.

**Step 4: Run check to verify the new state**

Run:

```bash
powershell -NoProfile -Command "(Get-Content 'C:\Users\admin\Downloads\NAI_NEW\pubspec.yaml') -match '^version:'"
```

Expected: output contains `version: 0.9.4`

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add pubspec.yaml
git commit -m "chore: bump app version to 0.9.4"
```

If `git status` reports this is not a repository, skip this step.

### Task 2: Rebuild the Windows Release output

**Files:**
- Refresh: `build/windows/x64/runner/Release`
- Read: `windows/runner/CMakeLists.txt`

**Step 1: Write the failing test**

Before rebuilding, inspect the current release exe version.

Run:

```bash
powershell -NoProfile -Command "(Get-Item 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\NAI_CasRand.exe').VersionInfo | Select-Object FileVersion,ProductVersion | Format-List"
```

Expected before rebuild: values are still the previous build version or the exe is missing.

**Step 2: Run check to confirm stale or missing build state**

Run the same command and record the current state.

**Step 3: Write minimal implementation**

Run a fresh Windows release build:

```bash
flutter build windows --release
```

Do not manually edit runner resource files.

**Step 4: Run checks to verify the rebuilt state**

Run:

```bash
powershell -NoProfile -Command "Test-Path 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\NAI_CasRand.exe'"
```

Expected: `True`

Then run:

```bash
powershell -NoProfile -Command "(Get-Item 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\NAI_CasRand.exe').VersionInfo | Select-Object FileVersion,ProductVersion | Format-List"
```

Expected: both `FileVersion` and `ProductVersion` reflect `0.9.4`

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add pubspec.yaml
git commit -m "build: refresh windows release for 0.9.4"
```

If `git status` reports this is not a repository, skip this step.

### Task 3: Verify splash/welcome and about version signals

**Files:**
- Verify indirectly via runtime behavior from: `lib/ui/navigation/widgets/navigation_view.dart`
- Verify indirectly via runtime behavior from: `lib/ui/navigation/widgets/navigation_appbar.dart`
- Read: `lib/ui/navigation/widgets/debug_settings_view.dart`

**Step 1: Write the failing test**

This is runtime verification. Define the exact expected behavior before launch:

- welcome dialog shows `0.9.4`
- about dialog shows `0.9.4`

If the welcome dialog does not appear because `welcomeMessageVersion` was already persisted to the current version, reset it before verification.

**Step 2: Run manual precondition setup**

If needed, use the existing debug reset path or clear the stored config so the welcome dialog is allowed to show again.

**Step 3: Write minimal implementation**

No additional production code should be needed if the build uses the new app version correctly.

**Step 4: Run manual verification**

Launch:

```bash
build\windows\x64\runner\Release\NAI_CasRand.exe
```

Manual checklist:

- welcome dialog title includes `0.9.4`
- about dialog shows version `0.9.4`

If welcome does not appear, reset `welcomeMessageVersion` and run again.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add pubspec.yaml
git commit -m "chore: verify windows version signals for 0.9.4"
```

If `git status` reports this is not a repository, skip this step.

### Task 4: Final release handoff verification

**Files:**
- Verify: `build/windows/x64/runner/Release`

**Step 1: Run final metadata verification**

Run:

```bash
powershell -NoProfile -Command "(Get-Item 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release\NAI_CasRand.exe').VersionInfo | Select-Object FileVersion,ProductVersion | Format-List"
```

Expected: both values show `0.9.4`

**Step 2: Run final file-presence verification**

Run:

```bash
powershell -NoProfile -Command "Get-ChildItem 'C:\Users\admin\Downloads\NAI_NEW\build\windows\x64\runner\Release' | Select-Object Name"
```

Expected: output includes `NAI_CasRand.exe`, `data`, `flutter_windows.dll`, and plugin dlls

**Step 3: Prepare user handoff note**

Document the exact runnable path:

- `build/windows/x64/runner/Release/NAI_CasRand.exe`

Also note that the entire `Release` directory must remain together.

**Step 4: Commit**

If this workspace is a git repository:

```bash
git add pubspec.yaml
git commit -m "build: prepare windows 0.9.4 release handoff"
```

If `git status` reports this is not a repository, skip this step.
