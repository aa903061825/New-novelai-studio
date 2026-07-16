import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fails the audit for incomplete source coverage without changing caches',
    () async {
      final fixture = await _CoverageFixture.create('complete');
      addTearDown(fixture.dispose);

      final covered = fixture.sourceDirectory('covered-script')..createSync();
      final noCache = fixture.sourceDirectory('nested/no-cache-script')
        ..createSync(recursive: true);
      final emptySource = fixture.sourceDirectory('empty-script')..createSync();
      final missingSource = Directory('${fixture.root.path}/missing-script');

      final cachedPng = File('${covered.path}/01-cached.png')
        ..writeAsBytesSync(_png());
      File('${covered.path}/02-second-cache.JPG')
          .writeAsBytesSync(const [0xff, 0xd8, 0xff, 0xd9]);
      File('${covered.path}/03-text.png').writeAsBytesSync(
        _png(
          chunkType: 'tEXt',
          keyword: 'Description',
          value: 'masterpiece, 1girl',
        ),
      );
      File('${covered.path}/04-ztxt.PNG').writeAsBytesSync(
        _png(
          chunkType: 'zTXt',
          keyword: 'Comment',
          value: jsonEncode({'prompt': '1boy, blue hair'}),
        ),
      );
      File('${covered.path}/05-itxt.png').writeAsBytesSync(
        _png(
          chunkType: 'iTXt',
          keyword: 'fullContent',
          value: jsonEncode({
            'v4_prompt': {
              'caption': {'base_caption': '1girl, red hair'},
            },
          }),
          compressedInternationalText: true,
        ),
      );
      File('${covered.path}/06-no-prompt.png').writeAsBytesSync(
        _png(
          chunkType: 'tEXt',
          keyword: 'Comment',
          value: jsonEncode({'seed': 12345}),
        ),
      );
      File('${covered.path}/07-uncached.webp')
          .writeAsBytesSync(ascii.encode('RIFFfixtureWEBP'));

      File('${noCache.path}/01-lonely.JPEG')
          .writeAsBytesSync(const [0xff, 0xd8, 0xff, 0xd9]);
      File('${noCache.path}/02-prompt.png').writeAsBytesSync(
        _png(
          chunkType: 'tEXt',
          keyword: 'Stealth_PNGInfo',
          value: jsonEncode({'prompt': '1girl, solo'}),
        ),
      );

      fixture.writeCache('a.json', {
        'scriptId': 'covered-a',
        'sourceRootPath': covered.path,
        'scriptSnapshot': {
          'frames': [
            _frame(1, sourceImagePath: cachedPng.path),
            _frame(
              99,
              sourceImagePath: '${covered.path}/99-missing.png',
            ),
          ],
        },
      });
      fixture.writeCache('b.json', {
        'scriptId': 'covered-b',
        'sourceRootPath': covered.path.replaceAll(r'\', '/'),
        'scriptSnapshot': {
          'frames': [_frame(2, fileName: '02-second-cache.JPG')],
        },
      });
      fixture.writeCache('empty.json', {
        'scriptId': 'empty',
        'sourceRootPath': emptySource.path,
        'scriptSnapshot': {
          'frames': [_frame(1, fileName: 'also-missing.webp')],
        },
      });
      fixture.writeCache('missing.json', {
        'scriptId': 'missing',
        'sourceRootPath': missingSource.path,
        'scriptSnapshot': {
          'frames': [_frame(1, fileName: 'ghost.png')],
        },
      });
      final cacheBytesBefore = fixture.cacheBytes();

      final firstResult = await fixture.runTool();

      expect(
        firstResult.exitCode,
        isNot(0),
        reason:
            'stdout:\n${firstResult.stdout}\nstderr:\n${firstResult.stderr}',
      );
      final firstReportBytes = fixture.report.readAsBytesSync();
      final report = fixture.readReport();
      expect(report['api_used'], isFalse);
      expect(report['read_only'], isTrue);
      expect(report['source_coverage_reviewed'], isFalse);
      expect(report['errors'], isEmpty);

      final checks = _map(report['checks']);
      expect(checks['errors'], isTrue);
      expect(checks['missing_cache_directory_count'], isFalse);
      expect(checks['cache_source_issue_count'], isFalse);
      expect(checks['missing_frame_image_count'], isFalse);
      expect(checks['uncached_png_with_prompt_metadata_count'], isFalse);
      expect(checks['uncached_png_metadata_error_count'], isTrue);
      expect(checks['uncached_png_without_prompt_metadata_reviewed'], isTrue);
      expect(checks['source_coverage_reviewed'], isFalse);

      final summary = _map(report['summary']);
      expect(summary['cache_file_count'], 4);
      expect(summary['cache_source_group_count'], 3);
      expect(summary['source_directory_count'], 2);
      expect(summary['source_image_count'], 9);
      expect(summary['missing_cache_directory_count'], 1);
      expect(summary['cache_source_issue_count'], 2);
      expect(summary['uncached_image_count'], 7);
      expect(summary['uncached_png_with_prompt_metadata_count'], 4);
      expect(summary['uncached_png_without_prompt_metadata_count'], 1);
      expect(summary['uncached_png_metadata_error_count'], 0);
      expect(summary['missing_frame_image_count'], 3);

      final violations = _maps(report['violations']);
      expect(
        {
          for (final violation in violations)
            violation['check']: violation['count'],
        },
        {
          'missing_cache_directory_count': 1,
          'cache_source_issue_count': 2,
          'missing_frame_image_count': 3,
          'uncached_png_with_prompt_metadata_count': 4,
        },
      );

      final sourceDirectories = _maps(report['source_directories']);
      final coveredRow = sourceDirectories.singleWhere(
        (row) => row['source_root_path'] == covered.resolveSymbolicLinksSync(),
      );
      expect(coveredRow['cache_files'], ['a.json', 'b.json']);
      expect(coveredRow['image_count'], 7);
      expect(coveredRow['cached_image_count'], 2);
      expect(coveredRow['uncached_image_count'], 5);

      final missingCacheDirectories =
          _maps(report['missing_cache_directories']);
      expect(missingCacheDirectories, hasLength(1));
      expect(
        missingCacheDirectories.single['source_root_path'],
        noCache.resolveSymbolicLinksSync(),
      );

      final sourceIssues = _maps(report['cache_source_issues']);
      expect(
        {
          for (final issue in sourceIssues)
            issue['status']: (issue['cache_files'] as List).single,
        },
        {'no_images': 'empty.json', 'path_not_found': 'missing.json'},
      );

      final uncachedImages = _maps(report['uncached_images']);
      expect(
        uncachedImages.map((row) => row['image_path']).toList(),
        orderedEquals(
          [...uncachedImages.map((row) => row['image_path'] as String)]..sort(),
        ),
      );
      expect(
        _byFileName(uncachedImages, '03-text.png')['prompt_metadata_status'],
        'usable',
      );
      expect(
        _byFileName(uncachedImages, '03-text.png')['png_text_chunk_types'],
        ['tEXt'],
      );
      expect(
        _byFileName(uncachedImages, '04-ztxt.PNG')['prompt_metadata_status'],
        'usable',
      );
      expect(
        _byFileName(uncachedImages, '04-ztxt.PNG')['png_text_chunk_types'],
        ['zTXt'],
      );
      expect(
        _byFileName(uncachedImages, '05-itxt.png')['prompt_metadata_status'],
        'usable',
      );
      expect(
        _byFileName(uncachedImages, '05-itxt.png')['png_text_chunk_types'],
        ['iTXt'],
      );
      expect(
        _byFileName(
            uncachedImages, '06-no-prompt.png')['prompt_metadata_status'],
        'not_usable',
      );
      expect(
        _byFileName(
            uncachedImages, '07-uncached.webp')['prompt_metadata_status'],
        'not_applicable',
      );
      expect(
        _byFileName(uncachedImages, '02-prompt.png')['prompt_metadata_status'],
        'usable',
      );

      final missingFrameImages = _maps(report['missing_frame_images']);
      expect(
        missingFrameImages.map((row) => row['cache_file']).toList(),
        ['a.json', 'empty.json', 'missing.json'],
      );
      expect(
        missingFrameImages.map((row) => row['frame_index']).toList(),
        [99, 1, 1],
      );

      final unrecoverableReview =
          _map(report['uncached_png_without_prompt_metadata_review']);
      expect(
        unrecoverableReview['status'],
        'reviewed_unrecoverable_without_metadata',
      );
      expect(unrecoverableReview['count'], 1);
      expect(
        unrecoverableReview['images'],
        contains(_byFileName(uncachedImages, '06-no-prompt.png')['image_path']),
      );

      expect(fixture.cacheBytes(), cacheBytesBefore);

      final secondResult = await fixture.runTool();
      expect(secondResult.exitCode, isNot(0));
      expect(fixture.report.readAsBytesSync(), firstReportBytes);
      expect(fixture.cacheBytes(), cacheBytesBefore);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'passes when the only uncached PNG is reviewed as unrecoverable without metadata',
    () async {
      final fixture =
          await _CoverageFixture.create('unrecoverable-no-metadata');
      addTearDown(fixture.dispose);

      final source = fixture.sourceDirectory('script')..createSync();
      final orphan = File('${source.path}/01-no-prompt.png')
        ..writeAsBytesSync(
          _png(
            chunkType: 'tEXt',
            keyword: 'Comment',
            value: jsonEncode({'seed': 12345}),
          ),
        );
      fixture.writeCache('script.json', {
        'scriptId': 'script',
        'sourceRootPath': source.path,
        'scriptSnapshot': {'frames': <Map<String, dynamic>>[]},
      });

      final result = await fixture.runTool();

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      final report = fixture.readReport();
      expect(report['source_coverage_reviewed'], isTrue);
      expect(report['errors'], isEmpty);
      expect(report['violations'], isEmpty);

      final summary = _map(report['summary']);
      expect(summary['missing_cache_directory_count'], 0);
      expect(summary['cache_source_issue_count'], 0);
      expect(summary['missing_frame_image_count'], 0);
      expect(summary['uncached_png_with_prompt_metadata_count'], 0);
      expect(summary['uncached_png_without_prompt_metadata_count'], 1);
      expect(summary['uncached_png_metadata_error_count'], 0);

      final checks = _map(report['checks']);
      for (final check in const [
        'errors',
        'missing_cache_directory_count',
        'cache_source_issue_count',
        'missing_frame_image_count',
        'uncached_png_with_prompt_metadata_count',
        'uncached_png_metadata_error_count',
        'uncached_png_without_prompt_metadata_reviewed',
        'source_coverage_reviewed',
      ]) {
        expect(checks[check], isTrue, reason: check);
      }

      final review =
          _map(report['uncached_png_without_prompt_metadata_review']);
      expect(review['status'], 'reviewed_unrecoverable_without_metadata');
      expect(review['count'], 1);
      expect(review['images'], contains(orphan.resolveSymbolicLinksSync()));
      expect(
        _byFileName(_maps(report['uncached_images']), '01-no-prompt.png')[
            'prompt_metadata_status'],
        'not_usable',
      );
    },
  );

  test('reports an incomplete audit when a cache cannot be parsed', () async {
    final fixture = await _CoverageFixture.create('parse-error');
    addTearDown(fixture.dispose);
    final source = fixture.sourceDirectory('script')..createSync();
    File('${source.path}/01.png').writeAsBytesSync(_png());
    final malformed = File('${fixture.cacheDir.path}/broken.json')
      ..writeAsStringSync('{ definitely not json');
    final before = malformed.readAsBytesSync();

    final result = await fixture.runTool();

    expect(result.exitCode, isNot(0));
    expect(fixture.report.existsSync(), isTrue);
    final report = fixture.readReport();
    expect(report['api_used'], isFalse);
    expect(report['read_only'], isTrue);
    expect(report['source_coverage_reviewed'], isFalse);
    final errors = _maps(report['errors']);
    expect(errors, hasLength(1));
    expect(errors.single['scope'], 'cache_parse');
    expect(errors.single['cache_file'], 'broken.json');
    expect(malformed.readAsBytesSync(), before);
  });
}

Map<String, dynamic> _frame(
  int index, {
  String? sourceImagePath,
  String? fileName,
}) {
  return {
    'index': index,
    if (sourceImagePath != null) 'sourceImagePath': sourceImagePath,
    if (fileName != null) 'fileName': fileName,
  };
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

List<Map<String, dynamic>> _maps(Object? value) =>
    (value! as List).map((entry) => _map(entry)).toList();

Map<String, dynamic> _byFileName(
  List<Map<String, dynamic>> rows,
  String fileName,
) =>
    rows.singleWhere((row) => row['file_name'] == fileName);

Uint8List _png({
  String? chunkType,
  String keyword = '',
  String value = '',
  bool compressedInternationalText = false,
}) {
  final bytes = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..add(
      _pngChunk(
        'IHDR',
        Uint8List.fromList([
          ..._uint32(1),
          ..._uint32(1),
          8,
          2,
          0,
          0,
          0,
        ]),
      ),
    );
  if (chunkType != null) {
    bytes.add(
      _pngChunk(
        chunkType,
        _pngTextData(
          chunkType,
          keyword,
          value,
          compressedInternationalText: compressedInternationalText,
        ),
      ),
    );
  }
  bytes
    ..add(
      _pngChunk(
        'IDAT',
        Uint8List.fromList(ZLibCodec().encode(const [0, 0, 0, 0])),
      ),
    )
    ..add(_pngChunk('IEND', Uint8List(0)));
  return bytes.toBytes();
}

Uint8List _pngTextData(
  String type,
  String keyword,
  String value, {
  required bool compressedInternationalText,
}) {
  final key = utf8.encode(keyword);
  final text = utf8.encode(value);
  switch (type) {
    case 'tEXt':
      return Uint8List.fromList([...key, 0, ...text]);
    case 'zTXt':
      return Uint8List.fromList([
        ...key,
        0,
        0,
        ...ZLibCodec().encode(text),
      ]);
    case 'iTXt':
      return Uint8List.fromList([
        ...key,
        0,
        if (compressedInternationalText) 1 else 0,
        0,
        0,
        0,
        ...(compressedInternationalText ? ZLibCodec().encode(text) : text),
      ]);
    default:
      throw ArgumentError.value(type, 'type');
  }
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  return Uint8List.fromList([
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(_crc32([...typeBytes, ...data])),
  ]);
}

Uint8List _uint32(int value) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

class _CoverageFixture {
  _CoverageFixture({
    required this.root,
    required this.cacheDir,
    required this.sourceRoot,
    required this.report,
  });

  final Directory root;
  final Directory cacheDir;
  final Directory sourceRoot;
  final File report;

  static Future<_CoverageFixture> create(String name) async {
    final root = await Directory.systemTemp.createTemp(
      'script-recast-source-coverage-$name-',
    );
    final cacheDir = Directory('${root.path}/cache')..createSync();
    final sourceRoot = Directory('${root.path}/source')..createSync();
    return _CoverageFixture(
      root: root,
      cacheDir: cacheDir,
      sourceRoot: sourceRoot,
      report: File('${root.path}/report.json'),
    );
  }

  Directory sourceDirectory(String relativePath) =>
      Directory('${sourceRoot.path}/$relativePath');

  void writeCache(String fileName, Map<String, dynamic> cache) {
    File('${cacheDir.path}/$fileName').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(cache)}\n',
      encoding: utf8,
    );
  }

  Map<String, List<int>> cacheBytes() => {
        for (final entity in cacheDir.listSync())
          if (entity is File)
            entity.path.split(Platform.pathSeparator).last:
                entity.readAsBytesSync(),
      };

  Future<ProcessResult> runTool() => Process.run(
        'node',
        [
          'tool/audit_script_recast_source_coverage_offline.mjs',
          '--cache-dir',
          cacheDir.path,
          '--source-root',
          sourceRoot.path,
          '--report',
          report.path,
        ],
        workingDirectory: Directory.current.path,
      );

  Map<String, dynamic> readReport() =>
      _map(jsonDecode(report.readAsStringSync(encoding: utf8)));

  Future<void> dispose() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}
