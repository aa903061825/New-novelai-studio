import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_evidence_builder.dart';

void main() {
  test('builds raw tag evidence chunks from slot base and negative captions',
      () {
    final script = Script(
      id: 'script-1',
      name: 'Opening scene',
      rootPath: '',
      detectedSchema: ScriptSchema.v4Slotted,
      frames: [
        _frame(
          1,
          baseCaption: 'official art, classroom, close-up',
          charCaptions: [
            'alice_(series), white shirt, standing, close-up',
          ],
          negativeBase: 'mosaic censoring, lowres',
          negativeCharCaptions: [
            'bad hands, mosaic censoring',
          ],
        ),
        _frame(
          2,
          baseCaption: 'official art, classroom, walking',
          charCaptions: [
            'alice_(series), white shirt, sitting',
          ],
          negativeBase: 'lowres',
        ),
        _frame(
          3,
          baseCaption: 'ignored base',
          charCaptions: ['ignored slot'],
          parseStatus: ScriptFrameParseStatus.error,
        ),
      ],
    );

    final chunks = const ScriptAiRoleEvidenceBuilder().buildChunks(
      script: script,
    );

    expect(chunks, hasLength(1));
    final chunk = chunks.single;
    expect(chunk['schema_version'], 2);
    expect(chunk['request_kind'], 'chunk_extract_v2');
    expect(chunk['chunk_id'], 'chunk-1');
    expect(chunk['script'], {
      'id': 'script-1',
      'name': 'Opening scene',
      'detected_schema': 'v4Slotted',
      'frame_count': 2,
    });
    expect(chunk['chunk'], {
      'start_frame_index': 1,
      'end_frame_index': 2,
      'frame_count': 2,
    });

    _expectNoOldCatalogKeys(chunk);

    final sources = (chunk['sources'] as List).cast<Map<String, dynamic>>();
    expect(sources.map((source) => source['source_kind']).toList(), [
      'base',
      'slot',
      'negative',
      'negative',
    ]);

    final slot =
        sources.singleWhere((source) => source['source_id'] == 'slot-0');
    expect(slot['source_kind'], 'slot');
    expect(_evidence(slot, 'white shirt'), {
      'tag': 'white shirt',
      'count': 2,
      'frame_indexes': [1, 2],
      'samples': [
        'alice_(series), white shirt, standing, close-up',
        'alice_(series), white shirt, sitting',
      ],
    });
    expect(_evidence(slot, 'standing')['frame_indexes'], [1]);
    expect(_evidence(slot, 'close-up')['samples'], [
      'alice_(series), white shirt, standing, close-up',
    ]);

    final base = sources.singleWhere((source) => source['source_id'] == 'base');
    expect(base['source_kind'], 'base');
    expect(_evidence(base, 'official art')['count'], 2);
    expect(_evidence(base, 'close-up')['frame_indexes'], [1]);

    final negativeBase = sources.singleWhere(
      (source) => source['source_id'] == 'negative-base',
    );
    expect(negativeBase['source_kind'], 'negative');
    expect(_evidence(negativeBase, 'mosaic censoring'), {
      'tag': 'mosaic censoring',
      'count': 1,
      'frame_indexes': [1],
      'samples': ['mosaic censoring, lowres'],
    });

    final negativeSlot = sources.singleWhere(
      (source) => source['source_id'] == 'negative-slot-0',
    );
    expect(negativeSlot['source_kind'], 'negative');
    expect(_evidence(negativeSlot, 'mosaic censoring')['samples'], [
      'bad hands, mosaic censoring',
    ]);
  });

  test('builds v2 chunks with timeline segments and tag evidence', () {
    final script = _script([
      _frame(
        1,
        baseCaption: 'school uniform, classroom',
        charCaptions: ['black coat, black pantyhose, shoes'],
      ),
      _frame(
        2,
        baseCaption: 'school uniform, classroom',
        charCaptions: ['black coat, black pantyhose, shoes'],
      ),
    ]);

    final chunks = const ScriptAiRoleEvidenceBuilder().buildChunks(
      script: script,
    );
    final chunk = chunks.single;
    final slot = (chunk['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['source_id'] == 'slot-0');

    expect(chunk['schema_version'], 2);
    expect(chunk['request_kind'], 'chunk_extract_v2');
    expect(slot['tag_evidence'], isA<List>());
    expect(slot['timeline_segments'], isA<List>());
    expect(slot['timeline_segments'], hasLength(1));
    expect(
      (slot['timeline_segments'] as List).single,
      containsPair(
        'representative_caption',
        'black coat, black pantyhose, shoes',
      ),
    );
    expect(
      (slot['timeline_segments'] as List).single,
      containsPair('frame_indexes', [1, 2]),
    );
  });

  test('surfaces exact cross-slot tag candidates for identity review', () {
    final script = _script([
      _frame(
        1,
        charCaptions: [
          'alice_(series), white shirt',
          'beth_(series), black dress',
        ],
      ),
      _frame(
        2,
        charCaptions: [
          'beth_(series), black dress',
          'alice_(series), white shirt',
        ],
      ),
    ]);

    final chunk =
        const ScriptAiRoleEvidenceBuilder().buildChunks(script: script).single;

    final candidates = (chunk['cross_slot_tag_candidates'] as List)
        .cast<Map<String, dynamic>>();
    final alice = candidates.singleWhere(
      (candidate) => candidate['tag'] == 'alice_(series)',
    );

    expect(alice['frame_indexes'], [1, 2]);
    expect(
      (alice['appearances'] as List).cast<Map<String, dynamic>>(),
      [
        {
          'source_id': 'slot-0',
          'source_kind': 'slot',
          'frame_indexes': [1],
        },
        {
          'source_id': 'slot-1',
          'source_kind': 'slot',
          'frame_indexes': [2],
        },
      ],
    );
  });

  test(
      'tag evidence normalizes weights while exact frame prompts keep source text',
      () {
    final script = _script([
      _frame(
        1,
        baseCaption: 'artist:test, 1.1::city lights::',
        charCaptions: ['1.25::blue eyes::, 0.75::white dress::'],
        negativeBase: '0.8::lowres::',
      ),
      _frame(2, charCaptions: ['green eyes']),
    ]);

    final chunk = const ScriptAiRoleEvidenceBuilder()
        .buildChunks(
          script: script,
        )
        .single;
    final slot = (chunk['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['source_id'] == 'slot-0');

    expect(_evidence(slot, 'blue eyes'), containsPair('tag', 'blue eyes'));
    expect(_evidence(slot, 'blue eyes'), isNot(contains('raw_tag')));
    expect(_evidence(slot, 'blue eyes'), isNot(contains('weight')));
    expect(
      (slot['timeline_segments'] as List)
          .cast<Map<String, dynamic>>()
          .map((segment) => segment['representative_caption']),
      contains('1.25::blue eyes::, 0.75::white dress::'),
    );

    expect(chunk['frame_prompts'], [
      {
        'frame_index': 1,
        'base_caption': 'artist:test, 1.1::city lights::',
        'char_captions': ['1.25::blue eyes::, 0.75::white dress::'],
        'negative_base': '0.8::lowres::',
        'negative_char_captions': <String>[],
      },
      {
        'frame_index': 2,
        'base_caption': '',
        'char_captions': ['green eyes'],
        'negative_base': '',
        'negative_char_captions': <String>[],
      },
    ]);
  });

  test('surfaces slotless base prompt frames without inferring a role', () {
    final chunk = const ScriptAiRoleEvidenceBuilder()
        .buildChunks(
          script: _script([
            _frame(
              1,
              baseCaption: 'alice_(series), white shirt, classroom',
              charCaptions: const [],
            ),
            _frame(
              2,
              baseCaption: 'beth_(series), black dress, classroom',
              charCaptions: const ['beth_(series), black dress'],
            ),
            _frame(
              3,
              baseCaption: 'car interior',
              charCaptions: const [''],
            ),
          ]),
        )
        .single;

    expect(chunk['slotless_base_prompt_frames'], [
      {
        'frame_index': 1,
        'source_id': 'base',
        'source_kind': 'base',
        'reason': 'no_nonempty_character_slots',
      },
      {
        'frame_index': 3,
        'source_id': 'base',
        'source_kind': 'base',
        'reason': 'no_nonempty_character_slots',
      },
    ]);
  });

  test('caption changes create separate timeline segments', () {
    final script = _script([
      _frame(1, charCaptions: ['school uniform, black pantyhose, shoes']),
      _frame(2, charCaptions: ['school uniform, black pantyhose, shoes']),
      _frame(3, charCaptions: ['school uniform, black pantyhose, no shoes']),
    ]);

    final chunk = const ScriptAiRoleEvidenceBuilder()
        .buildChunks(
          script: script,
        )
        .single;
    final slot = (chunk['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['source_id'] == 'slot-0');
    final segments =
        (slot['timeline_segments'] as List).cast<Map<String, dynamic>>();

    expect(segments, hasLength(2));
    expect(segments[0]['frame_range'], [1, 2]);
    expect(segments[1]['frame_range'], [3, 3]);
    expect(segments[1]['variant_tags'], contains('no shoes'));
  });

  test('timeline segment count is capped deterministically', () {
    final frames = [
      for (var index = 1; index <= 20; index += 1)
        _frame(index, charCaptions: ['outfit tag $index']),
    ];

    final chunk = const ScriptAiRoleEvidenceBuilder(
      maxTimelineSegmentsPerSource: 12,
    ).buildChunks(script: _script(frames)).single;
    final slot = (chunk['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['source_id'] == 'slot-0');
    final segments =
        (slot['timeline_segments'] as List).cast<Map<String, dynamic>>();

    expect(segments, hasLength(12));
    expect(segments.first['frame_range'], [1, 1]);
    expect(segments.last['frame_range'], [20, 20]);
  });

  test('timeline segment cap of two keeps first and last segments', () {
    final frames = [
      for (var index = 1; index <= 5; index += 1)
        _frame(index, charCaptions: ['unique outfit tag $index']),
    ];

    final chunk = const ScriptAiRoleEvidenceBuilder(
      maxTimelineSegmentsPerSource: 2,
    ).buildChunks(script: _script(frames)).single;
    final slot = (chunk['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['source_id'] == 'slot-0');
    final segments =
        (slot['timeline_segments'] as List).cast<Map<String, dynamic>>();

    expect(segments.map((segment) => segment['frame_range']).toList(), [
      [1, 1],
      [5, 5],
    ]);
  });

  test('timeline segment cap breaks equal-length middle ties by earliest start',
      () {
    final frames = [
      _frame(1, charCaptions: ['opening pose']),
      _frame(2, charCaptions: ['middle pose a']),
      _frame(3, charCaptions: ['middle pose a']),
      _frame(4, charCaptions: ['middle pose b']),
      _frame(5, charCaptions: ['middle pose b']),
      _frame(6, charCaptions: ['middle pose c']),
      _frame(7, charCaptions: ['middle pose c']),
      _frame(8, charCaptions: ['closing pose']),
    ];

    final chunk = const ScriptAiRoleEvidenceBuilder(
      maxTimelineSegmentsPerSource: 4,
    ).buildChunks(script: _script(frames)).single;
    final slot = (chunk['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['source_id'] == 'slot-0');
    final segments =
        (slot['timeline_segments'] as List).cast<Map<String, dynamic>>();

    expect(segments.map((segment) => segment['frame_range']).toList(), [
      [1, 1],
      [2, 3],
      [4, 5],
      [8, 8],
    ]);
  });

  test('timeline segment cap ranks middle candidates by true segment length',
      () {
    final frames = [
      _frame(1, charCaptions: ['opening pose']),
      _frame(2, charCaptions: ['middle pose a']),
      _frame(3, charCaptions: ['middle pose a']),
      _frame(4, charCaptions: ['middle pose a']),
      _frame(5, charCaptions: ['middle pose b']),
      _frame(6, charCaptions: ['middle pose b']),
      _frame(7, charCaptions: ['middle pose b']),
      _frame(8, charCaptions: ['middle pose b']),
      _frame(9, charCaptions: ['closing pose']),
    ];

    final chunk = const ScriptAiRoleEvidenceBuilder(
      maxFrameIndexesPerTag: 2,
      maxTimelineSegmentsPerSource: 3,
    ).buildChunks(script: _script(frames)).single;
    final slot = (chunk['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['source_id'] == 'slot-0');
    final segments =
        (slot['timeline_segments'] as List).cast<Map<String, dynamic>>();

    expect(segments.map((segment) => segment['frame_range']).toList(), [
      [1, 1],
      [5, 8],
      [9, 9],
    ]);
    expect(segments.map((segment) => segment['frame_indexes']).toList(), [
      [1],
      [5, 6],
      [9],
    ]);
  });

  test('chunks by parsed frame order and caps frame indexes and samples', () {
    final script = Script(
      id: 'script-1',
      name: 'Opening scene',
      rootPath: '',
      detectedSchema: ScriptSchema.v4Slotted,
      frames: [
        _frame(10, charCaptions: ['white shirt, standing']),
        _frame(20, charCaptions: ['white shirt, sitting']),
        _frame(30, charCaptions: ['white shirt, walking']),
      ],
    );

    final chunks = const ScriptAiRoleEvidenceBuilder(
      maxFramesPerChunk: 2,
      maxFrameIndexesPerTag: 1,
      maxSamplesPerTag: 2,
    ).buildChunks(script: script);

    expect(chunks, hasLength(2));
    expect(chunks.first['chunk'], {
      'start_frame_index': 10,
      'end_frame_index': 20,
      'frame_count': 2,
    });
    expect(chunks.last['chunk'], {
      'start_frame_index': 30,
      'end_frame_index': 30,
      'frame_count': 1,
    });

    final sources =
        (chunks.first['sources'] as List).cast<Map<String, dynamic>>();
    final slot =
        sources.singleWhere((source) => source['source_id'] == 'slot-0');
    final whiteShirt = _evidence(slot, 'white shirt');
    expect(whiteShirt['count'], 2);
    expect(whiteShirt['frame_indexes'], [10]);
    expect(whiteShirt['samples'], [
      'white shirt, standing',
      'white shirt, sitting',
    ]);
  });
}

Script _script(List<ScriptFrame> frames) {
  return Script(
    id: 'script-1',
    name: 'Opening scene',
    rootPath: '',
    detectedSchema: ScriptSchema.v4Slotted,
    frames: frames,
  );
}

Map<String, dynamic> _evidence(Map<String, dynamic> source, String tag) {
  final evidence =
      (source['tag_evidence'] as List).cast<Map<String, dynamic>>();
  return evidence.singleWhere((item) => item['tag'] == tag);
}

void _expectNoOldCatalogKeys(Map<String, dynamic> chunk) {
  expect(chunk, isNot(contains('asset_catalog')));
  expect(chunk, isNot(contains('characters')));
  expect(chunk, isNot(contains('outfits')));
  expect(chunk, isNot(contains('vibes')));
}

ScriptFrame _frame(
  int index, {
  String baseCaption = '',
  List<String> charCaptions = const [],
  String negativeBase = '',
  List<String> negativeCharCaptions = const [],
  ScriptFrameParseStatus parseStatus = ScriptFrameParseStatus.parsed,
}) {
  return ScriptFrame(
    index: index,
    fileName: 'nai_$index.json',
    sourcePath: '',
    rawJson: '{}',
    parsed: ParsedFrame(
      baseCaption: baseCaption,
      charCaptions: charCaptions,
      negativeBase: negativeBase,
      negativeCharCaptions: negativeCharCaptions,
    ),
    detectedSchema: ScriptSchema.v4Slotted,
    parseStatus: parseStatus,
  );
}
