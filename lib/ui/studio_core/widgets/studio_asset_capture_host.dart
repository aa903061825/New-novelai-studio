import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/save_asset_confirm_bar.dart';

class StudioAssetCaptureHost extends StatefulWidget {
  final Widget child;
  final StudioAssetCaptureService service;
  final ValueChanged<StudioAssetCaptureResult>? onSaved;

  const StudioAssetCaptureHost({
    super.key,
    required this.child,
    required this.service,
    this.onSaved,
  });

  static StudioAssetCaptureHostState? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_StudioAssetCaptureScope>()
        ?.state;
  }

  static StudioAssetCaptureHostState of(BuildContext context) {
    final state = maybeOf(context);
    if (state == null) {
      throw FlutterError(
        'StudioAssetCaptureHost.of() called with a context that does not '
        'contain a StudioAssetCaptureHost.',
      );
    }
    return state;
  }

  @override
  State<StudioAssetCaptureHost> createState() => StudioAssetCaptureHostState();
}

class StudioAssetCaptureHostState extends State<StudioAssetCaptureHost> {
  StudioAssetCaptureDraft? _draft;
  StudioAssetCapturePlan? _plan;
  String _name = '';
  String _note = '';
  String? _selectedTargetId;
  bool _forceNew = true;
  bool _saving = false;
  int _previewRequestToken = 0;
  int _activeDraftToken = 0;
  int _saveRequestToken = 0;

  Future<void> showDraft(StudioAssetCaptureDraft draft) async {
    final requestToken = ++_previewRequestToken;
    _saveRequestToken++;
    final plan = await widget.service.previewSave(draft);
    if (!mounted || requestToken != _previewRequestToken) return;
    final firstTarget =
        plan.candidates.isEmpty ? null : plan.candidates.first.id;
    setState(() {
      _activeDraftToken++;
      _draft = plan.draft;
      _plan = plan;
      _name = plan.draft.name;
      _note = plan.draft.note;
      _selectedTargetId = firstTarget;
      _forceNew = firstTarget == null;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _StudioAssetCaptureScope(
      state: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_draft case final draft?)
            if (_plan case final plan?)
              Positioned.fill(
                child: _AssetCaptureModalLayer(
                  isSaving: _saving,
                  onDismiss: _clear,
                  child: SaveAssetConfirmBar(
                    key: ValueKey(_activeDraftToken),
                    draft: draft,
                    plan: plan,
                    name: _name,
                    note: _note,
                    selectedTargetId: _selectedTargetId,
                    forceNew: _forceNew,
                    isSaving: _saving,
                    onNameChanged: (value) => _name = value,
                    onNoteChanged: (value) => _note = value,
                    onKindChanged: _changeKind,
                    onTargetChanged: (value) {
                      setState(() => _selectedTargetId = value);
                    },
                    onForceNewChanged: (value) {
                      setState(() => _forceNew = value);
                    },
                    onCancel: _clear,
                    onConfirm: _confirm,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _changeKind(StudioAssetCaptureKind kind) async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final requestToken = ++_previewRequestToken;
    final nextDraft = draft.copyWith(kind: kind, name: _name, note: _note);
    setState(() {
      _activeDraftToken++;
      _draft = nextDraft;
      _plan = StudioAssetCapturePlan(draft: nextDraft);
      _selectedTargetId = null;
      _forceNew = true;
    });
    final plan = await widget.service.previewSave(nextDraft);
    if (!mounted || requestToken != _previewRequestToken) return;
    final firstTarget =
        plan.candidates.isEmpty ? null : plan.candidates.first.id;
    setState(() {
      _plan = plan;
      _selectedTargetId = firstTarget;
      _forceNew = firstTarget == null;
    });
  }

  Future<void> _confirm() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final activeDraftToken = _activeDraftToken;
    final saveToken = ++_saveRequestToken;
    setState(() => _saving = true);
    try {
      final result = await widget.service.save(
        draft,
        targetId: _selectedTargetId,
        forceNew: _forceNew,
        nameOverride: _name,
        noteOverride: _note,
      );
      if (!mounted ||
          saveToken != _saveRequestToken ||
          activeDraftToken != _activeDraftToken) {
        return;
      }
      widget.onSaved?.call(result);
      _showSnackBar('Saved ${result.name}.');
      _clear();
    } catch (error) {
      if (!mounted ||
          saveToken != _saveRequestToken ||
          activeDraftToken != _activeDraftToken) {
        return;
      }
      setState(() => _saving = false);
      _showSnackBar('Save failed: $error');
    }
  }

  void _clear() {
    _previewRequestToken++;
    _saveRequestToken++;
    setState(() {
      _activeDraftToken++;
      _draft = null;
      _plan = null;
      _name = '';
      _note = '';
      _selectedTargetId = null;
      _forceNew = true;
      _saving = false;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _AssetCaptureModalLayer extends StatelessWidget {
  final Widget child;
  final bool isSaving;
  final VoidCallback onDismiss;

  const _AssetCaptureModalLayer({
    required this.child,
    required this.isSaving,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('save-asset-modal-layer'),
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('save-asset-modal-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: isSaving ? null : onDismiss,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.58),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 760,
                  maxHeight: 560,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: DecoratedBox(
                    key: const Key('save-asset-modal'),
                    decoration: BoxDecoration(
                      color: StudioTokens.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: StudioTokens.cardOutline),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xCC000000),
                          blurRadius: 36,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudioAssetCaptureScope extends InheritedWidget {
  final StudioAssetCaptureHostState state;

  const _StudioAssetCaptureScope({
    required this.state,
    required super.child,
  });

  @override
  bool updateShouldNotify(_StudioAssetCaptureScope oldWidget) {
    return oldWidget.state != state;
  }
}
