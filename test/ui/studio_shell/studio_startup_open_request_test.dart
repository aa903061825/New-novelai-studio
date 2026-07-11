import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/studio_shell/models/studio_startup_open_request.dart';

void main() {
  test('parses script id from startup arguments', () {
    final request = StudioStartupOpenRequest.fromArgs(
      const ['--open-script', 'script-01c52bffa4037de8'],
    );

    expect(request, isNotNull);
    expect(request!.scriptId, 'script-01c52bffa4037de8');
    expect(request.sourceFolder, isNull);
    expect(request.frameIndex, isNull);
  });

  test('parses equals-style source folder and frame arguments', () {
    final request = StudioStartupOpenRequest.fromArgs(
      const [
        '--script-id=script-quick',
        r'--script-source=E:\stories\quick',
        '--script-frame=12',
      ],
    );

    expect(request, isNotNull);
    expect(request!.scriptId, 'script-quick');
    expect(request.sourceFolder, r'E:\stories\quick');
    expect(request.frameIndex, 12);
  });

  test('ignores unrelated arguments', () {
    expect(
      StudioStartupOpenRequest.fromArgs(const ['--foo', 'bar']),
      isNull,
    );
  });
}
