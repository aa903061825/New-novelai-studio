class StudioStartupOpenRequest {
  final String scriptId;
  final String? sourceFolder;
  final int? frameIndex;

  const StudioStartupOpenRequest({
    required this.scriptId,
    this.sourceFolder,
    this.frameIndex,
  });

  static StudioStartupOpenRequest? fromArgs(List<String> args) {
    final scriptId = _argumentValue(
      args,
      const ['--open-script', '--script-id', '--open-script-id'],
    );
    final normalizedScriptId = scriptId?.trim();
    if (normalizedScriptId == null || normalizedScriptId.isEmpty) {
      return null;
    }

    final sourceFolder = _argumentValue(
      args,
      const ['--open-script-source', '--script-source'],
    )?.trim();
    final frameText = _argumentValue(
      args,
      const ['--open-script-frame', '--script-frame'],
    )?.trim();
    final frameIndex =
        frameText == null || frameText.isEmpty ? null : int.tryParse(frameText);

    return StudioStartupOpenRequest(
      scriptId: normalizedScriptId,
      sourceFolder:
          sourceFolder == null || sourceFolder.isEmpty ? null : sourceFolder,
      frameIndex: frameIndex == null || frameIndex < 1 ? null : frameIndex,
    );
  }
}

String? _argumentValue(List<String> args, List<String> names) {
  for (var i = 0; i < args.length; i += 1) {
    final arg = args[i];
    for (final name in names) {
      if (arg == name) {
        if (i + 1 >= args.length) {
          return null;
        }
        final next = args[i + 1];
        return next.startsWith('--') ? null : next;
      }
      final prefix = '$name=';
      if (arg.startsWith(prefix)) {
        return arg.substring(prefix.length);
      }
    }
  }
  return null;
}
