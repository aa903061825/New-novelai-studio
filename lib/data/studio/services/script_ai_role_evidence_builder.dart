import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';

class ScriptAiRoleEvidenceBuilder {
  final int maxFramesPerChunk;
  final int maxFrameIndexesPerTag;
  final int maxSamplesPerTag;
  final int maxTimelineSegmentsPerSource;

  const ScriptAiRoleEvidenceBuilder({
    this.maxFramesPerChunk = 80,
    this.maxFrameIndexesPerTag = 24,
    this.maxSamplesPerTag = 3,
    this.maxTimelineSegmentsPerSource = 12,
  });

  List<Map<String, dynamic>> buildChunks({required Script script}) {
    final parsedFrames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    if (parsedFrames.isEmpty) {
      return const [];
    }

    final chunkSize =
        maxFramesPerChunk <= 0 ? parsedFrames.length : maxFramesPerChunk;
    final chunks = <Map<String, dynamic>>[];
    for (var start = 0; start < parsedFrames.length; start += chunkSize) {
      final endExclusive = (start + chunkSize).clamp(0, parsedFrames.length);
      final frames = parsedFrames.sublist(start, endExclusive);
      chunks.add(
          _chunkMap(script, parsedFrames.length, chunks.length + 1, frames));
    }
    return List.unmodifiable(chunks);
  }

  Map<String, dynamic> _chunkMap(
    Script script,
    int parsedFrameCount,
    int chunkNumber,
    List<ScriptFrame> frames,
  ) {
    final sources = <String, _SourceAccumulator>{};

    for (final frame in frames) {
      _addCaption(
        sources,
        sourceId: 'base',
        sourceKind: 'base',
        frameIndex: frame.index,
        caption: frame.parsed.baseCaption,
      );

      for (final (slotIndex, caption) in frame.parsed.charCaptions.indexed) {
        _addCaption(
          sources,
          sourceId: 'slot-$slotIndex',
          sourceKind: 'slot',
          frameIndex: frame.index,
          caption: caption,
        );
      }

      _addCaption(
        sources,
        sourceId: 'negative-base',
        sourceKind: 'negative',
        frameIndex: frame.index,
        caption: frame.parsed.negativeBase,
      );

      for (final (slotIndex, caption)
          in frame.parsed.negativeCharCaptions.indexed) {
        _addCaption(
          sources,
          sourceId: 'negative-slot-$slotIndex',
          sourceKind: 'negative',
          frameIndex: frame.index,
          caption: caption,
        );
      }
    }

    return {
      'schema_version': 2,
      'request_kind': 'chunk_extract_v2',
      'chunk_id': 'chunk-$chunkNumber',
      'script': {
        'id': script.id,
        'name': script.name,
        'detected_schema': script.detectedSchema.name,
        'frame_count': parsedFrameCount,
      },
      'chunk': {
        'start_frame_index': frames.first.index,
        'end_frame_index': frames.last.index,
        'frame_count': frames.length,
      },
      'frame_prompts': [
        for (final frame in frames) _framePromptMap(frame),
      ],
      'slotless_base_prompt_frames': _slotlessBasePromptFrames(frames),
      'sources': [
        for (final source in sources.values) source.toJson(),
      ],
      'cross_slot_tag_candidates': _crossSlotTagCandidates(sources.values),
    };
  }

  Map<String, dynamic> _framePromptMap(ScriptFrame frame) {
    return {
      'frame_index': frame.index,
      'base_caption': frame.parsed.baseCaption,
      'char_captions': List.unmodifiable(frame.parsed.charCaptions),
      'negative_base': frame.parsed.negativeBase,
      'negative_char_captions':
          List.unmodifiable(frame.parsed.negativeCharCaptions),
    };
  }

  List<Map<String, dynamic>> _slotlessBasePromptFrames(
    List<ScriptFrame> frames,
  ) {
    return List.unmodifiable([
      for (final frame in frames)
        if (frame.parsed.baseCaption.trim().isNotEmpty &&
            !_hasNonEmptyCharacterSlot(frame))
          {
            'frame_index': frame.index,
            'source_id': 'base',
            'source_kind': 'base',
            'reason': 'no_nonempty_character_slots',
          },
    ]);
  }

  bool _hasNonEmptyCharacterSlot(ScriptFrame frame) {
    return frame.parsed.charCaptions
        .any((caption) => caption.trim().isNotEmpty);
  }

  void _addCaption(
    Map<String, _SourceAccumulator> sources, {
    required String sourceId,
    required String sourceKind,
    required int frameIndex,
    required String caption,
  }) {
    final rawCaption = caption.trim();
    if (rawCaption.isEmpty) {
      return;
    }

    final source = sources.putIfAbsent(
      sourceId,
      () => _SourceAccumulator(
        sourceId: sourceId,
        sourceKind: sourceKind,
        maxFrameIndexesPerTag: maxFrameIndexesPerTag,
        maxSamplesPerTag: maxSamplesPerTag,
        maxTimelineSegments: maxTimelineSegmentsPerSource,
      ),
    );
    source.addCaption(frameIndex: frameIndex, caption: rawCaption);

    for (final rawTag in PromptTagProcessor.splitWorkshopTags(rawCaption)) {
      final display = PromptTagProcessor.cleanTagDisplay(rawTag);
      final key = PromptTagProcessor.normalizeMatchKey(display);
      if (display.isEmpty || key.isEmpty) {
        continue;
      }

      source.addTag(
        tagKey: key,
        tagDisplay: display,
        frameIndex: frameIndex,
        sample: rawCaption,
      );
    }
  }
}

List<Map<String, dynamic>> _crossSlotTagCandidates(
  Iterable<_SourceAccumulator> sources,
) {
  final candidates = <String, _CrossSlotTagCandidate>{};
  for (final source in sources) {
    if (source.sourceKind != 'slot') {
      continue;
    }
    for (final entry in source.tagEntries) {
      candidates
          .putIfAbsent(
            entry.key,
            () => _CrossSlotTagCandidate(tag: entry.value.tag),
          )
          .add(
            sourceId: source.sourceId,
            sourceKind: source.sourceKind,
            frameIndexes: entry.value.frameIndexes,
          );
    }
  }
  final result = [
    for (final candidate in candidates.values)
      if (candidate.isCrossSlot) candidate.toJson(),
  ]..sort((left, right) => (left['tag'] as String).compareTo(
        right['tag'] as String,
      ));
  return List.unmodifiable(result);
}

class _CrossSlotTagCandidate {
  final String tag;
  final Map<String, _CrossSlotAppearance> _appearances = {};

  _CrossSlotTagCandidate({required this.tag});

  bool get isCrossSlot => _appearances.length > 1;

  void add({
    required String sourceId,
    required String sourceKind,
    required List<int> frameIndexes,
  }) {
    _appearances
        .putIfAbsent(
          sourceId,
          () => _CrossSlotAppearance(
            sourceId: sourceId,
            sourceKind: sourceKind,
          ),
        )
        .addFrameIndexes(frameIndexes);
  }

  Map<String, dynamic> toJson() {
    final appearances = _appearances.values.toList()
      ..sort((left, right) => left.sourceId.compareTo(right.sourceId));
    return {
      'tag': tag,
      'frame_indexes': _limitedFrameIndexes(
        [
          for (final appearance in appearances) ...appearance.frameIndexes,
        ],
        0,
      ),
      'appearances': [
        for (final appearance in appearances) appearance.toJson(),
      ],
    };
  }
}

class _CrossSlotAppearance {
  final String sourceId;
  final String sourceKind;
  final List<int> frameIndexes = [];

  _CrossSlotAppearance({
    required this.sourceId,
    required this.sourceKind,
  });

  void addFrameIndexes(Iterable<int> indexes) {
    final seen = frameIndexes.toSet();
    for (final index in indexes) {
      if (seen.add(index)) {
        frameIndexes.add(index);
      }
    }
    frameIndexes.sort();
  }

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'source_kind': sourceKind,
        'frame_indexes': List.unmodifiable(frameIndexes),
      };
}

class _CaptionEvent {
  final int frameIndex;
  final String caption;
  final String normalizedCaption;
  final List<String> tags;
  final Set<String> tagKeys;

  const _CaptionEvent({
    required this.frameIndex,
    required this.caption,
    required this.normalizedCaption,
    required this.tags,
    required this.tagKeys,
  });
}

class _SourceAccumulator {
  final String sourceId;
  final String sourceKind;
  final int maxFrameIndexesPerTag;
  final int maxSamplesPerTag;
  final int maxTimelineSegments;
  final List<_CaptionEvent> _captionEvents = [];
  final Map<String, _TagEvidenceAccumulator> _tags = {};

  _SourceAccumulator({
    required this.sourceId,
    required this.sourceKind,
    required this.maxFrameIndexesPerTag,
    required this.maxSamplesPerTag,
    required this.maxTimelineSegments,
  });

  void addCaption({
    required int frameIndex,
    required String caption,
  }) {
    final tags = _captionTags(caption);
    if (tags.isEmpty) {
      return;
    }
    _captionEvents.add(
      _CaptionEvent(
        frameIndex: frameIndex,
        caption: caption,
        normalizedCaption: _normalizedCaptionKey(caption),
        tags: tags,
        tagKeys: tags
            .map(PromptTagProcessor.normalizeMatchKey)
            .where((tag) => tag.isNotEmpty)
            .toSet(),
      ),
    );
  }

  void addTag({
    required String tagKey,
    required String tagDisplay,
    required int frameIndex,
    required String sample,
  }) {
    final tag = _tags.putIfAbsent(
      tagKey,
      () => _TagEvidenceAccumulator(
        tag: tagDisplay,
        maxFrameIndexes: maxFrameIndexesPerTag,
        maxSamples: maxSamplesPerTag,
      ),
    );
    tag.add(
      frameIndex: frameIndex,
      sample: sample,
    );
  }

  Iterable<MapEntry<String, _TagEvidenceAccumulator>> get tagEntries =>
      _tags.entries;

  List<_TimelineSegment> _timelineSegments() {
    if (_captionEvents.isEmpty) return const [];
    final segments = <_TimelineSegment>[];
    var current = <_CaptionEvent>[];
    for (final event in _captionEvents) {
      if (current.isEmpty ||
          current.first.normalizedCaption == event.normalizedCaption) {
        current.add(event);
        continue;
      }
      segments.add(_segmentFromEvents(current));
      current = [event];
    }
    if (current.isNotEmpty) {
      segments.add(_segmentFromEvents(current));
    }
    return _limitedSegments(segments);
  }

  _TimelineSegment _segmentFromEvents(List<_CaptionEvent> events) {
    final first = events.first;
    final frameIndexes = _limitedFrameIndexes(
      [for (final event in events) event.frameIndex],
      maxFrameIndexesPerTag,
    );
    return _TimelineSegment(
      startFrameIndex: first.frameIndex,
      endFrameIndex: events.last.frameIndex,
      representativeCaption: first.caption,
      tags: first.tags,
      tagKeys: first.tagKeys,
      frameIndexes: frameIndexes,
      frameCount: events.length,
    );
  }

  List<_TimelineSegment> _limitedSegments(List<_TimelineSegment> segments) {
    if (maxTimelineSegments <= 0 || segments.length <= maxTimelineSegments) {
      return List.unmodifiable(segments);
    }
    final selected = <_TimelineSegment>[];
    void addSegment(_TimelineSegment segment) {
      if (!selected.any((item) =>
          item.startFrameIndex == segment.startFrameIndex &&
          item.endFrameIndex == segment.endFrameIndex)) {
        selected.add(segment);
      }
    }

    final firstCount = maxTimelineSegments >= 2 ? 1 : maxTimelineSegments;
    final lastCount = maxTimelineSegments >= 2 ? 1 : 0;
    for (final segment in segments.take(firstCount)) {
      addSegment(segment);
    }
    for (final segment in segments.reversed.take(lastCount).toList().reversed) {
      addSegment(segment);
    }

    final remaining = [...segments]..sort((left, right) {
        final lengthComparison = right.frameCount.compareTo(left.frameCount);
        if (lengthComparison != 0) return lengthComparison;
        return left.startFrameIndex.compareTo(right.startFrameIndex);
      });
    for (final segment in remaining) {
      if (selected.length >= maxTimelineSegments) break;
      addSegment(segment);
    }
    selected.sort(
        (left, right) => left.startFrameIndex.compareTo(right.startFrameIndex));
    return List.unmodifiable(selected);
  }

  Map<String, dynamic> toJson() {
    final segments = _timelineSegments();
    return {
      'source_id': sourceId,
      'source_kind': sourceKind,
      'timeline_segments': [
        for (final (index, segment) in segments.indexed)
          segment.toJson(
            previousKeys:
                index == 0 ? const <String>{} : segments[index - 1].tagKeys,
            nextKeys: index + 1 >= segments.length
                ? const <String>{}
                : segments[index + 1].tagKeys,
          ),
      ],
      'tag_evidence': [
        for (final tag in _tags.values) tag.toJson(),
      ],
    };
  }
}

class _TimelineSegment {
  final int startFrameIndex;
  final int endFrameIndex;
  final String representativeCaption;
  final List<String> tags;
  final Set<String> tagKeys;
  final List<int> frameIndexes;
  final int frameCount;

  const _TimelineSegment({
    required this.startFrameIndex,
    required this.endFrameIndex,
    required this.representativeCaption,
    required this.tags,
    required this.tagKeys,
    required this.frameIndexes,
    required this.frameCount,
  });

  Map<String, dynamic> toJson({
    required Set<String> previousKeys,
    required Set<String> nextKeys,
  }) {
    final neighborKeys = {...previousKeys, ...nextKeys};
    final variantTags = [
      for (final tag in tags)
        if (!neighborKeys.contains(PromptTagProcessor.normalizeMatchKey(tag)))
          tag,
    ];
    return {
      'frame_range': [startFrameIndex, endFrameIndex],
      'representative_caption': representativeCaption,
      'stable_tags': tags,
      'variant_tags': variantTags,
      'frame_indexes': frameIndexes,
    };
  }
}

class _TagEvidenceAccumulator {
  final String tag;
  final int maxFrameIndexes;
  final int maxSamples;
  var _count = 0;
  final List<int> _frameIndexes = [];
  final List<String> _samples = [];

  _TagEvidenceAccumulator({
    required this.tag,
    required this.maxFrameIndexes,
    required this.maxSamples,
  });

  List<int> get frameIndexes => List.unmodifiable(_frameIndexes);

  void add({
    required int frameIndex,
    required String sample,
  }) {
    _count += 1;
    if (maxFrameIndexes > 0 &&
        _frameIndexes.length < maxFrameIndexes &&
        !_frameIndexes.contains(frameIndex)) {
      _frameIndexes.add(frameIndex);
    }
    if (maxSamples > 0 && _samples.length < maxSamples) {
      _samples.add(sample);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'tag': tag,
      'count': _count,
      'frame_indexes': List.unmodifiable(_frameIndexes),
      'samples': List.unmodifiable(_samples),
    };
  }
}

String _normalizedCaptionKey(String caption) {
  final tags = PromptTagProcessor.splitWorkshopTags(caption)
      .map(PromptTagProcessor.cleanTagDisplay)
      .map(PromptTagProcessor.normalizeMatchKey)
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false)
    ..sort();
  return tags.join('|');
}

List<String> _captionTags(String caption) {
  final seen = <String>{};
  final tags = <String>[];
  for (final rawTag in PromptTagProcessor.splitWorkshopTags(caption)) {
    final display = PromptTagProcessor.cleanTagDisplay(rawTag).trim();
    final key = PromptTagProcessor.normalizeMatchKey(display);
    if (display.isEmpty || key.isEmpty || !seen.add(key)) {
      continue;
    }
    tags.add(display);
  }
  return List.unmodifiable(tags);
}

List<int> _limitedFrameIndexes(List<int> indexes, int limit) {
  final seen = <int>{};
  final result = <int>[];
  for (final index in indexes) {
    if (limit > 0 && result.length >= limit) break;
    if (seen.add(index)) result.add(index);
  }
  return List.unmodifiable(result);
}
