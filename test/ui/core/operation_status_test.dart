import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/core/operation_status.dart';

void main() {
  test('status keeps stable kind separate from display message', () {
    const status = OperationStatus.failure(
      code: OperationStatusCode.importFailed,
      message: '导入失败：文件损坏',
      recoverable: true,
    );

    expect(status.kind, OperationStatusKind.failure);
    expect(status.code, OperationStatusCode.importFailed);
    expect(status.message, '导入失败：文件损坏');
    expect(status.recoverable, isTrue);
  });

  test('idle and running helpers have predictable defaults', () {
    expect(const OperationStatus.idle().message, '');
    expect(
      const OperationStatus.running(
        code: OperationStatusCode.cacheRestore,
        message: '正在恢复缓存',
      ).recoverable,
      isFalse,
    );
  });
}
