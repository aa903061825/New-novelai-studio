import 'dart:async' show Completer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/studio_core/widgets/save_asset_confirm_bar.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_asset_capture_host.dart';

void main() {
  group('SaveAssetConfirmBar', () {
    testWidgets('edits name and note before confirming', (tester) async {
      String? changedName;
      String? changedNote;
      var confirmed = false;
      var cancelled = false;

      await tester.pumpWidget(
        _material(
          SaveAssetConfirmBar(
            draft: _artistDraft(),
            plan: StudioAssetCapturePlan(draft: _artistDraft()),
            name: 'Initial name',
            note: 'Initial note',
            forceNew: true,
            onNameChanged: (value) => changedName = value,
            onNoteChanged: (value) => changedNote = value,
            onKindChanged: (_) {},
            onTargetChanged: (_) {},
            onForceNewChanged: (_) {},
            onCancel: () => cancelled = true,
            onConfirm: () => confirmed = true,
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('save-asset-name-field')),
        'Edited name',
      );
      await tester.enterText(
        find.byKey(const Key('save-asset-note-field')),
        'Edited note',
      );
      await tester.tap(find.byKey(const Key('save-asset-cancel')));
      await tester.tap(find.byKey(const Key('save-asset-confirm')));

      expect(changedName, 'Edited name');
      expect(changedNote, 'Edited note');
      expect(cancelled, isTrue);
      expect(confirmed, isTrue);
    });

    testWidgets('selecting create-new clears target and forces new save',
        (tester) async {
      String? changedTarget = 'existing-artist';
      bool? changedForceNew;
      final draft = _artistDraft();

      await tester.pumpWidget(
        _material(
          SaveAssetConfirmBar(
            draft: draft,
            plan: StudioAssetCapturePlan(
              draft: draft,
              candidates: const [
                StudioAssetDuplicateCandidate(
                  kind: StudioAssetCaptureKind.artistChain,
                  id: 'existing-artist',
                  name: 'Existing artist',
                  summary: 'artist:a',
                ),
              ],
            ),
            name: draft.name,
            note: draft.note,
            selectedTargetId: 'existing-artist',
            forceNew: false,
            onNameChanged: (_) {},
            onNoteChanged: (_) {},
            onKindChanged: (_) {},
            onTargetChanged: (value) => changedTarget = value,
            onForceNewChanged: (value) => changedForceNew = value,
            onCancel: () {},
            onConfirm: () {},
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('save-asset-target-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建素材').last);
      await tester.pumpAndSettle();

      expect(changedTarget, isNull);
      expect(changedForceNew, isTrue);
      expect(find.text('新建素材'), findsOneWidget);
    });

    testWidgets('candidate names use ellipsis overflow', (tester) async {
      final draft = _artistDraft();
      const longName =
          'Existing artist with a very long name that should not overflow';

      await tester.pumpWidget(
        _material(
          SaveAssetConfirmBar(
            draft: draft,
            plan: StudioAssetCapturePlan(
              draft: draft,
              candidates: const [
                StudioAssetDuplicateCandidate(
                  kind: StudioAssetCaptureKind.artistChain,
                  id: 'existing-artist',
                  name: longName,
                  summary: 'artist:a',
                ),
              ],
            ),
            name: draft.name,
            note: draft.note,
            selectedTargetId: 'existing-artist',
            forceNew: false,
            onNameChanged: (_) {},
            onNoteChanged: (_) {},
            onKindChanged: (_) {},
            onTargetChanged: (_) {},
            onForceNewChanged: (_) {},
            onCancel: () {},
            onConfirm: () {},
          ),
        ),
      );

      final label = tester.widget<Text>(find.text(longName));
      expect(label.overflow, TextOverflow.ellipsis);
    });

    testWidgets('kind dropdown reports selected kind', (tester) async {
      StudioAssetCaptureKind? changedKind;
      final draft = _artistDraft();

      await tester.pumpWidget(
        _material(
          SaveAssetConfirmBar(
            draft: draft,
            plan: StudioAssetCapturePlan(draft: draft),
            name: draft.name,
            note: draft.note,
            forceNew: true,
            onNameChanged: (_) {},
            onNoteChanged: (_) {},
            onKindChanged: (value) => changedKind = value,
            onTargetChanged: (_) {},
            onForceNewChanged: (_) {},
            onCancel: () {},
            onConfirm: () {},
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('save-asset-kind-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('画师串').last);
      await tester.pumpAndSettle();

      expect(changedKind, StudioAssetCaptureKind.artistChain);
    });

    testWidgets('uses Chinese labels throughout the confirmation form',
        (tester) async {
      final draft = _artistDraft();

      await tester.pumpWidget(
        _material(
          SaveAssetConfirmBar(
            draft: draft,
            plan: StudioAssetCapturePlan(
              draft: draft,
              candidates: const [
                StudioAssetDuplicateCandidate(
                  kind: StudioAssetCaptureKind.artistChain,
                  id: 'existing-artist',
                  name: '已有画师串',
                  summary: 'artist:a',
                ),
              ],
            ),
            name: '源画师串 1',
            note: draft.note,
            selectedTargetId: 'existing-artist',
            forceNew: false,
            onNameChanged: (_) {},
            onNoteChanged: (_) {},
            onKindChanged: (_) {},
            onTargetChanged: (_) {},
            onForceNewChanged: (_) {},
            onCancel: () {},
            onConfirm: () {},
          ),
        ),
      );

      for (final text in [
        '素材',
        '类型',
        '画师串',
        '名称',
        '源画师串 1',
        '备注',
        '合并目标',
        '取消',
        '保存'
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      for (final text in [
        'asset',
        'Type',
        'artist chain',
        'Name',
        'Source artist chain 1',
        'Note',
        'Merge target',
        'Cancel',
        'Save'
      ]) {
        expect(find.text(text), findsNothing);
      }
    });
  });

  group('StudioAssetCaptureHost', () {
    testWidgets('keeps newer draft when older preview resolves last',
        (tester) async {
      final service = _QueuedCaptureService();
      StudioAssetCaptureHostState? host;

      await tester.pumpWidget(
        _material(
          StudioAssetCaptureHost(
            service: service,
            child: Builder(
              builder: (context) {
                host = StudioAssetCaptureHost.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final first = _artistDraft(name: 'First draft', note: 'First note');
      final second = _artistDraft(name: 'Second draft', note: 'Second note');
      unawaited(host!.showDraft(first));
      unawaited(host!.showDraft(second));

      service.completePreview(
        second,
        StudioAssetCapturePlan(draft: second),
      );
      await tester.pump();
      service.completePreview(first, StudioAssetCapturePlan(draft: first));
      await tester.pumpAndSettle();

      expect(_fieldText(tester, 'save-asset-name-field'), 'Second draft');
      expect(_fieldText(tester, 'save-asset-note-field'), 'Second note');
    });

    testWidgets('older save completion does not clear newer overlay',
        (tester) async {
      final service = _QueuedCaptureService();
      StudioAssetCaptureHostState? host;

      await tester.pumpWidget(
        _material(
          StudioAssetCaptureHost(
            service: service,
            child: Builder(
              builder: (context) {
                host = StudioAssetCaptureHost.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final first = _artistDraft(name: 'First draft', note: 'First note');
      final second = _artistDraft(name: 'Second draft', note: 'Second note');
      unawaited(host!.showDraft(first));
      service.completePreview(first, StudioAssetCapturePlan(draft: first));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save-asset-confirm')));
      await tester.pump();

      unawaited(host!.showDraft(second));
      service.completePreview(
        second,
        StudioAssetCapturePlan(draft: second),
      );
      await tester.pumpAndSettle();

      service.completeSave(
        StudioAssetCaptureResult(
          kind: first.kind,
          savedId: 'first-saved',
          name: first.name,
          merged: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save-asset-confirm')), findsOneWidget);
      expect(_fieldText(tester, 'save-asset-name-field'), 'Second draft');
      expect(_fieldText(tester, 'save-asset-note-field'), 'Second note');
    });

    testWidgets('replacing visible draft refreshes name and note fields',
        (tester) async {
      final service = _FakeCaptureService();
      StudioAssetCaptureHostState? host;

      await tester.pumpWidget(
        _material(
          StudioAssetCaptureHost(
            service: service,
            child: Builder(
              builder: (context) {
                host = StudioAssetCaptureHost.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await host!
          .showDraft(_artistDraft(name: 'First draft', note: 'First note'));
      await tester.pumpAndSettle();
      await host!.showDraft(
        _artistDraft(name: 'Second draft', note: 'Second note'),
      );
      await tester.pumpAndSettle();

      expect(_fieldText(tester, 'save-asset-name-field'), 'Second draft');
      expect(_fieldText(tester, 'save-asset-note-field'), 'Second note');
    });

    testWidgets('showDraft presents a recognizable modal confirmation surface',
        (tester) async {
      final service = _FakeCaptureService();
      StudioAssetCaptureHostState? host;

      await tester.pumpWidget(
        _material(
          StudioAssetCaptureHost(
            service: service,
            child: Builder(
              builder: (context) {
                host = StudioAssetCaptureHost.maybeOf(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      await host!.showDraft(_artistDraft());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save-asset-modal-scrim')), findsOneWidget);
      expect(find.byKey(const Key('save-asset-modal')), findsOneWidget);
      expect(find.text('保存素材'), findsOneWidget);

      final modalRect =
          tester.getRect(find.byKey(const Key('save-asset-modal')));
      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(modalRect.width, lessThan(screenSize.width));
      expect(modalRect.left, greaterThan(0));
      expect(modalRect.right, lessThan(screenSize.width));
    });

    testWidgets('showDraft saves selected candidate and clears overlay',
        (tester) async {
      final service = _FakeCaptureService(
        candidates: const [
          StudioAssetDuplicateCandidate(
            kind: StudioAssetCaptureKind.artistChain,
            id: 'existing-artist',
            name: 'Existing artist',
            summary: 'artist:a',
          ),
        ],
      );
      StudioAssetCaptureResult? savedResult;

      await tester.pumpWidget(
        _material(
          StudioAssetCaptureHost(
            service: service,
            onSaved: (result) => savedResult = result,
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    final host = StudioAssetCaptureHost.maybeOf(context);
                    expect(host, isNotNull);
                    host!.showDraft(_artistDraft());
                  },
                  child: const Text('capture'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('capture'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('save-asset-name-field')),
        'Edited host name',
      );
      await tester.enterText(
        find.byKey(const Key('save-asset-note-field')),
        'Edited host note',
      );
      await tester.tap(find.byKey(const Key('save-asset-confirm')));
      await tester.pumpAndSettle();

      expect(service.savedDraft?.kind, StudioAssetCaptureKind.artistChain);
      expect(service.savedTargetId, 'existing-artist');
      expect(service.savedForceNew, isFalse);
      expect(service.savedNameOverride, 'Edited host name');
      expect(service.savedNoteOverride, 'Edited host note');
      expect(savedResult?.savedId, 'saved-artist');
      expect(find.byKey(const Key('save-asset-confirm')), findsNothing);
      expect(find.text('Saved Edited host name.'), findsOneWidget);
    });

    testWidgets('save error keeps overlay visible and shows snackbar',
        (tester) async {
      final service = _FakeCaptureService(
        saveError: const StudioAssetCaptureException('nope'),
      );

      await tester.pumpWidget(
        _material(
          StudioAssetCaptureHost(
            service: service,
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    StudioAssetCaptureHost.of(context)
                        .showDraft(_artistDraft());
                  },
                  child: const Text('capture'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('capture'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-asset-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save-asset-confirm')), findsOneWidget);
      expect(find.textContaining('nope'), findsOneWidget);
    });
  });
}

Widget _material(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

StudioAssetCaptureDraft _artistDraft({
  String name = 'Draft artist',
  String note = 'Draft note',
}) {
  return StudioAssetCaptureDraft.artistChain(
    name: name,
    note: note,
    source: _source,
    artistChain: const ArtistChain(
      id: 'artist-draft',
      name: 'Draft artist',
      tags: ['artist:a'],
    ),
  );
}

String _fieldText(WidgetTester tester, String key) {
  final editable = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(EditableText),
  );
  return tester.widget<EditableText>(editable).controller.text;
}

void unawaited(Future<void> future) {}

const _source = StudioAssetCaptureSource(
  surface: 'test',
  label: 'Test',
  sourceId: 'source-1',
);

class _FakeCaptureService extends StudioAssetCaptureService {
  _FakeCaptureService({
    this.candidates = const [],
    this.saveError,
  }) : super(workspaceService: WorkspaceService());

  final List<StudioAssetDuplicateCandidate> candidates;
  final Object? saveError;
  StudioAssetCaptureDraft? savedDraft;
  String? savedTargetId;
  bool? savedForceNew;
  String? savedNameOverride;
  String? savedNoteOverride;

  @override
  Future<StudioAssetCapturePlan> previewSave(
    StudioAssetCaptureDraft draft,
  ) async {
    return StudioAssetCapturePlan(draft: draft, candidates: candidates);
  }

  @override
  Future<StudioAssetCaptureResult> save(
    StudioAssetCaptureDraft draft, {
    String? targetId,
    bool forceNew = false,
    String? nameOverride,
    String? noteOverride,
  }) async {
    savedDraft = draft;
    savedTargetId = targetId;
    savedForceNew = forceNew;
    savedNameOverride = nameOverride;
    savedNoteOverride = noteOverride;
    final error = saveError;
    if (error != null) {
      throw error;
    }
    return StudioAssetCaptureResult(
      kind: draft.kind,
      savedId: 'saved-artist',
      name: nameOverride ?? draft.name,
      merged: !forceNew,
    );
  }
}

class _QueuedCaptureService extends StudioAssetCaptureService {
  _QueuedCaptureService() : super(workspaceService: WorkspaceService());

  final List<_PendingPreview> _previewQueue = [];
  final List<Completer<StudioAssetCaptureResult>> _saveQueue = [];

  @override
  Future<StudioAssetCapturePlan> previewSave(
    StudioAssetCaptureDraft draft,
  ) {
    final completer = Completer<StudioAssetCapturePlan>();
    _previewQueue.add(_PendingPreview(draft, completer));
    return completer.future;
  }

  void completePreview(
    StudioAssetCaptureDraft draft,
    StudioAssetCapturePlan plan,
  ) {
    final index = _previewQueue.indexWhere((entry) => entry.draft == draft);
    final entry = _previewQueue.removeAt(index);
    entry.completer.complete(plan);
  }

  @override
  Future<StudioAssetCaptureResult> save(
    StudioAssetCaptureDraft draft, {
    String? targetId,
    bool forceNew = false,
    String? nameOverride,
    String? noteOverride,
  }) {
    final completer = Completer<StudioAssetCaptureResult>();
    _saveQueue.add(completer);
    return completer.future;
  }

  void completeSave(StudioAssetCaptureResult result) {
    _saveQueue.removeAt(0).complete(result);
  }
}

class _PendingPreview {
  final StudioAssetCaptureDraft draft;
  final Completer<StudioAssetCapturePlan> completer;

  _PendingPreview(this.draft, this.completer);
}
