import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

typedef PromptTagDragRemover = void Function(Set<int> indexes);
typedef PromptTagSelectionSnapshotProvider = List<PromptTagSelectionItem>
    Function();
typedef PromptTagDragRemovalPolicy = bool Function(PromptTagDragData data);

class PromptTagDragData {
  final String originId;
  final Set<String> sourceFieldIds;
  final Set<int> indexes;
  final List<String> tags;
  final PromptTagDragRemover? removeFromSource;

  PromptTagDragData({
    required this.originId,
    Set<String>? sourceFieldIds,
    required Set<int> indexes,
    required List<String> tags,
    this.removeFromSource,
  })  : sourceFieldIds = Set.unmodifiable(sourceFieldIds ?? {originId}),
        indexes = Set.unmodifiable(indexes),
        tags = List.unmodifiable(tags);
}

class PromptTagDragFeedback extends StatelessWidget {
  final List<String> tags;
  final bool dense;

  const PromptTagDragFeedback({
    super.key,
    required this.tags,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final count = tags.length;
    final first = tags.isEmpty ? '' : tags.first;
    final label = count <= 1 ? first : '$count tags';
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StudioTokens.surface4,
          borderRadius: StudioTokens.radiusTag,
          border: Border.all(color: StudioTokens.primary),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 10,
            vertical: dense ? 5 : 7,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: StudioTokens.primary,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
      ),
    );
  }
}

@immutable
class PromptTagSelectionKey {
  final String fieldId;
  final int index;

  const PromptTagSelectionKey({
    required this.fieldId,
    required this.index,
  });

  @override
  bool operator ==(Object other) {
    return other is PromptTagSelectionKey &&
        other.fieldId == fieldId &&
        other.index == index;
  }

  @override
  int get hashCode => Object.hash(fieldId, index);
}

class PromptTagSelectionItem {
  final String fieldId;
  final int index;
  final String tag;
  final Rect globalRect;

  const PromptTagSelectionItem({
    required this.fieldId,
    required this.index,
    required this.tag,
    required this.globalRect,
  });

  PromptTagSelectionKey get key => PromptTagSelectionKey(
        fieldId: fieldId,
        index: index,
      );
}

class PromptTagSelectionField {
  final String fieldId;
  final String? selectionGroupId;
  final PromptTagSelectionSnapshotProvider snapshots;
  final PromptTagDragRemover removeIndexes;

  const PromptTagSelectionField({
    required this.fieldId,
    this.selectionGroupId,
    required this.snapshots,
    required this.removeIndexes,
  });
}

class _PromptTagSelectionHit {
  final PromptTagSelectionField field;
  final PromptTagSelectionItem item;

  const _PromptTagSelectionHit({
    required this.field,
    required this.item,
  });
}

class PromptTagSelectionController extends ChangeNotifier {
  final Map<String, PromptTagSelectionField> _fields =
      <String, PromptTagSelectionField>{};
  final Set<PromptTagSelectionKey> _selected = <PromptTagSelectionKey>{};
  final Set<PromptTagSelectionKey> _previewed = <PromptTagSelectionKey>{};
  late final String dragOriginId =
      'prompt-tag-shared-${identityHashCode(this)}';

  bool get hasSelection => _selected.isNotEmpty;
  int get selectedCount => _selected.length;

  int selectedCountFor(String fieldId) {
    return _selected.where((entry) => entry.fieldId == fieldId).length;
  }

  void registerField(PromptTagSelectionField field) {
    _fields[field.fieldId] = field;
  }

  void unregisterField(String fieldId) {
    _fields.remove(fieldId);
    final removedSelected = _selected
        .where((entry) => entry.fieldId == fieldId)
        .toList(growable: false);
    final removedPreviewed = _previewed
        .where((entry) => entry.fieldId == fieldId)
        .toList(growable: false);
    if (removedSelected.isEmpty && removedPreviewed.isEmpty) {
      return;
    }
    _selected.removeAll(removedSelected);
    _previewed.removeAll(removedPreviewed);
    notifyListeners();
  }

  bool isSelected(String fieldId, int index) {
    return _selected.contains(
      PromptTagSelectionKey(fieldId: fieldId, index: index),
    );
  }

  bool isPreviewed(String fieldId, int index) {
    return _previewed.contains(
      PromptTagSelectionKey(fieldId: fieldId, index: index),
    );
  }

  Set<int> selectedIndexesFor(String fieldId) {
    return _selected
        .where((entry) => entry.fieldId == fieldId)
        .map((entry) => entry.index)
        .toSet();
  }

  void clear() {
    if (_selected.isEmpty && _previewed.isEmpty) {
      return;
    }
    _selected.clear();
    _previewed.clear();
    notifyListeners();
  }

  void clearPreview() {
    if (_previewed.isEmpty) {
      return;
    }
    _previewed.clear();
    notifyListeners();
  }

  void toggle(
    String fieldId,
    int index, {
    bool additive = false,
  }) {
    final key = PromptTagSelectionKey(fieldId: fieldId, index: index);
    final onlySelected = _selected.length == 1 && _selected.contains(key);
    if (additive) {
      final groupId = _selectionGroupIdForField(fieldId);
      _selected.removeWhere(
        (entry) => _selectionGroupIdForField(entry.fieldId) != groupId,
      );
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    } else if (onlySelected) {
      _selected.clear();
    } else {
      _selected
        ..clear()
        ..add(key);
    }
    _previewed.clear();
    notifyListeners();
  }

  void setFieldSelection(
    String fieldId,
    Set<int> indexes, {
    bool additive = false,
  }) {
    if (!additive) {
      _selected.clear();
    } else {
      final groupId = _selectionGroupIdForField(fieldId);
      _selected.removeWhere(
        (entry) => _selectionGroupIdForField(entry.fieldId) != groupId,
      );
    }
    for (final index in indexes) {
      _selected.add(PromptTagSelectionKey(fieldId: fieldId, index: index));
    }
    _previewed.clear();
    notifyListeners();
  }

  void previewIntersecting(
    Rect globalRect, {
    bool additive = false,
    Offset? anchorPosition,
  }) {
    final next = _selectionKeysIntersecting(
      globalRect,
      additive: additive,
      anchorPosition: anchorPosition,
    );
    if (_setsEqual(_previewed, next)) {
      return;
    }
    _previewed
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void selectIntersecting(
    Rect globalRect, {
    bool additive = false,
    Offset? anchorPosition,
  }) {
    final next = _selectionKeysIntersecting(
      globalRect,
      additive: additive,
      anchorPosition: anchorPosition,
    );
    final changed = !_setsEqual(_selected, next) || _previewed.isNotEmpty;
    _selected
      ..clear()
      ..addAll(next);
    _previewed.clear();
    if (changed) {
      notifyListeners();
    }
  }

  bool hasItemAt(Offset globalPosition) {
    for (final field in _fields.values.toList().reversed) {
      for (final item in field.snapshots().reversed) {
        if (item.globalRect.contains(globalPosition)) {
          return true;
        }
      }
    }
    return false;
  }

  PromptTagDragData dragDataFor({
    required String fieldId,
    required String localOriginId,
    required Set<int> localIndexes,
    required List<String> localTags,
    required PromptTagDragRemover localRemove,
  }) {
    final groupId = _selectionGroupIdForField(fieldId);
    final selectedInGroup = _selected
        .where(
          (selected) => _selectionGroupIdForField(selected.fieldId) == groupId,
        )
        .toSet();
    final selectedFields = {
      for (final selected in selectedInGroup) selected.fieldId,
    };
    if (selectedInGroup.isEmpty ||
        !selectedFields.contains(fieldId) ||
        (selectedFields.length == 1 && selectedFields.contains(fieldId))) {
      return PromptTagDragData(
        originId: localOriginId,
        sourceFieldIds: {fieldId},
        indexes: localIndexes,
        tags: localTags,
        removeFromSource: localRemove,
      );
    }

    return PromptTagDragData(
      originId: dragOriginId,
      sourceFieldIds: selectedFields,
      indexes: selectedIndexesFor(fieldId),
      tags: _selectedTagsFor(selectedInGroup),
      removeFromSource: (_) => _removeSelectedFromSourcesInGroup(groupId),
    );
  }

  List<String> selectedTags() {
    return _selectedTagsFor(_selected);
  }

  List<String> _selectedTagsFor(Set<PromptTagSelectionKey> selection) {
    final result = <String>[];
    for (final field in _fields.values) {
      final selectedIndexes = selection
          .where((entry) => entry.fieldId == field.fieldId)
          .map((entry) => entry.index)
          .toSet();
      if (selectedIndexes.isEmpty) {
        continue;
      }
      final items = field
          .snapshots()
          .where((item) => selectedIndexes.contains(item.index))
          .toList(growable: false)
        ..sort((a, b) => a.index.compareTo(b.index));
      result.addAll(items.map((item) => item.tag));
    }
    return result;
  }

  void removeSelectedFromSources() {
    _removeSelectedFromSources(_selected);
  }

  void _removeSelectedFromSourcesInGroup(String? selectionGroupId) {
    final selectedInGroup = _selected
        .where(
          (selected) =>
              _selectionGroupIdForField(selected.fieldId) == selectionGroupId,
        )
        .toSet();
    _removeSelectedFromSources(selectedInGroup);
  }

  void _removeSelectedFromSources(Set<PromptTagSelectionKey> selection) {
    final byField = <String, Set<int>>{};
    for (final selected in selection) {
      byField.putIfAbsent(selected.fieldId, () => <int>{}).add(selected.index);
    }
    if (byField.isEmpty) {
      return;
    }
    _selected.removeAll(selection);
    _previewed.clear();
    for (final entry in byField.entries) {
      _fields[entry.key]?.removeIndexes(entry.value);
    }
    notifyListeners();
  }

  Set<PromptTagSelectionKey> _selectionKeysIntersecting(
    Rect globalRect, {
    required bool additive,
    Offset? anchorPosition,
  }) {
    final hits = _intersectingHits(globalRect);
    final groupId = _selectionGroupIdForHits(
      hits,
      anchorPosition: anchorPosition,
    );
    final next = additive
        ? _selected
            .where(
              (entry) => _selectionGroupIdForField(entry.fieldId) == groupId,
            )
            .toSet()
        : <PromptTagSelectionKey>{};
    for (final hit in hits) {
      if (hit.field.selectionGroupId == groupId) {
        next.add(hit.item.key);
      }
    }
    return next;
  }

  List<_PromptTagSelectionHit> _intersectingHits(Rect globalRect) {
    final hits = <_PromptTagSelectionHit>[];
    for (final field in _fields.values) {
      for (final item in field.snapshots()) {
        if (globalRect.overlaps(item.globalRect)) {
          hits.add(_PromptTagSelectionHit(field: field, item: item));
        }
      }
    }
    return hits;
  }

  String? _selectionGroupIdForHits(
    List<_PromptTagSelectionHit> hits, {
    Offset? anchorPosition,
  }) {
    if (hits.isEmpty) {
      return null;
    }
    if (anchorPosition == null) {
      return hits.first.field.selectionGroupId;
    }
    var nearest = hits.first;
    var nearestDistance = _distanceSquaredToRect(
      anchorPosition,
      nearest.item.globalRect,
    );
    for (final hit in hits.skip(1)) {
      final distance = _distanceSquaredToRect(
        anchorPosition,
        hit.item.globalRect,
      );
      if (distance < nearestDistance) {
        nearest = hit;
        nearestDistance = distance;
      }
    }
    return nearest.field.selectionGroupId;
  }

  String? _selectionGroupIdForField(String fieldId) {
    return _fields[fieldId]?.selectionGroupId;
  }

  double _distanceSquaredToRect(Offset point, Rect rect) {
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : point.dx > rect.right
            ? point.dx - rect.right
            : 0.0;
    final dy = point.dy < rect.top
        ? rect.top - point.dy
        : point.dy > rect.bottom
            ? point.dy - rect.bottom
            : 0.0;
    return dx * dx + dy * dy;
  }

  bool _setsEqual(
    Set<PromptTagSelectionKey> left,
    Set<PromptTagSelectionKey> right,
  ) {
    return left.length == right.length && left.containsAll(right);
  }
}
