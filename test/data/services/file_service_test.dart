import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/services/file_service.dart';

void main() {
  test('revealInFileManager passes Explorer select path as a separate argument',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'novel studio reveal test ',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}generated result.png',
    )..writeAsBytesSync([1, 2, 3]);
    final calls = <({String executable, List<String> arguments})>[];
    final service = FileService(
      startProcess: (executable, arguments, {required mode}) async {
        calls.add((executable: executable, arguments: arguments));
      },
    );

    await service.revealInFileManager(imageFile.path);

    if (Platform.isWindows) {
      expect(calls, hasLength(1));
      expect(calls.single.executable, 'explorer.exe');
      expect(calls.single.arguments, ['/select,', imageFile.absolute.path]);
    }
  });
}
