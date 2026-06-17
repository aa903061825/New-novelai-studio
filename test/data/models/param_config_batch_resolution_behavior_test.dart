import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/param_config.dart';

void main() {
  test('batch resolution parser keeps duplicate valid rows', () {
    final config = ParamConfig(
      enableBatchResolution: true,
      batchResolutionText: [
        '832x1216',
        '1024x1024',
        '832x1216',
        '832x1216',
      ].join('\n'),
    );

    final list = config.parseBatchResolutions();

    expect(list.length, 4);
    expect(list[0].width, 832);
    expect(list[0].height, 1216);
    expect(list[1].width, 1024);
    expect(list[1].height, 1024);
    expect(list[2].width, 832);
    expect(list[2].height, 1216);
    expect(list[3].width, 832);
    expect(list[3].height, 1216);
  });

  test('stop_at_end consumes duplicate rows in order', () {
    final config = ParamConfig(
      enableBatchResolution: true,
      batchResolutionMode: 'stop_at_end',
      batchResolutionText: [
        '832x1216',
        '832x1216',
        '1024x1024',
      ].join('\n'),
    );

    config.resetBatchResolutionCursor();

    final first = config.takeBatchResolution();
    final second = config.takeBatchResolution();
    final third = config.takeBatchResolution();
    final fourth = config.takeBatchResolution();

    expect(first, isNotNull);
    expect(first!.width, 832);
    expect(first.height, 1216);
    expect(second, isNotNull);
    expect(second!.width, 832);
    expect(second.height, 1216);
    expect(third, isNotNull);
    expect(third!.width, 1024);
    expect(third.height, 1024);
    expect(fourth, isNull);
  });
}
