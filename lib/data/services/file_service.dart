import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:saver_gallery/saver_gallery.dart';

typedef FileManagerProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments, {
  required ProcessStartMode mode,
});

class FileService {
  final FileManagerProcessStarter _startProcess;

  FileService({FileManagerProcessStarter? startProcess})
      : _startProcess = startProcess ?? _defaultStartProcess;

  static Future<void> _defaultStartProcess(
    String executable,
    List<String> arguments, {
    required ProcessStartMode mode,
  }) async {
    await Process.start(executable, arguments, mode: mode);
  }

  Future<String> resolvePictureSavePath(
    String fileName,
    String saveDir,
  ) async {
    if (Platform.isWindows) {
      final targetDir = await _windowsPictureSaveDirectory(saveDir);
      return _joinWindowsPath(targetDir.path, fileName);
    }
    return fileName;
  }

  Future<void> savePictureToFile(
    Uint8List bytes,
    String fileName,
    String saveDir,
  ) async {
    if (Platform.isWindows) {
      // Windows: create save path and write file
      final targetDir = await _windowsPictureSaveDirectory(saveDir);
      final file = File(_joinWindowsPath(targetDir.path, fileName));
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(bytes);
    } else if (Platform.isAndroid) {
      // Android: save as photo in Pictures/
      await _requestAlbumPermission();
      await SaverGallery.saveImage(
        bytes,
        fileName: fileName,
        androidRelativePath: "Pictures/nai-generated",
        skipIfExists: false,
      );
    }
  }

  Future<bool> saveStringToFile(
    String content,
    String fileName,
  ) async {
    if (Platform.isWindows) {
      final path = await FilePicker.platform.saveFile(fileName: fileName);
      if (path == null) return false;
      final file = File(path);
      await file.writeAsBytes(utf8.encode(content));
      return true;
    } else if (Platform.isAndroid) {
      final path = await FilePicker.platform.saveFile(
        fileName: fileName,
        bytes: utf8.encode(content),
      );
      return path != null;
    }
    return false;
  }

  Future<void> revealInFileManager(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('File path is empty.');
    }
    final file = File(trimmed).absolute;
    if (!await file.exists()) {
      throw StateError('File does not exist: ${file.path}');
    }
    if (Platform.isWindows) {
      await _startDetached(
        'explorer.exe',
        ['/select,', file.path],
      );
      return;
    }
    if (Platform.isMacOS) {
      await _startDetached(
        'open',
        ['-R', file.path],
      );
      return;
    }
    if (Platform.isLinux) {
      await _startDetached(
        'xdg-open',
        [file.parent.path],
      );
      return;
    }
    throw UnsupportedError(
      'Opening the file location is not supported on this platform.',
    );
  }

  Future<void> openDirectoryInFileManager(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Directory path is empty.');
    }
    final directory = Directory(trimmed).absolute;
    if (!await directory.exists()) {
      throw StateError('Directory does not exist: ${directory.path}');
    }
    if (Platform.isWindows) {
      await _startDetached(
        'explorer.exe',
        [directory.path],
      );
      return;
    }
    if (Platform.isMacOS) {
      await _startDetached(
        'open',
        [directory.path],
      );
      return;
    }
    if (Platform.isLinux) {
      await _startDetached(
        'xdg-open',
        [directory.path],
      );
      return;
    }
    throw UnsupportedError(
      'Opening the directory is not supported on this platform.',
    );
  }

  Future<void> _startDetached(String executable, List<String> arguments) {
    return _startProcess(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    );
  }

  String generateRandomString() {
    const length = 6;
    const lettersAndDigits = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();

    return List.generate(
        length,
        (index) =>
            lettersAndDigits[random.nextInt(lettersAndDigits.length)]).join();
  }

  String generateTimestampString(DateTime time) {
    return '${time.year}'
        '${time.month.toString().padLeft(2, '0')}'
        '${time.day.toString().padLeft(2, '0')}'
        '${time.hour.toString().padLeft(2, '0')}'
        '${time.minute.toString().padLeft(2, '0')}'
        '${time.second.toString().padLeft(2, '0')}';
  }

  Future<Uint8List?> decryptAsset(String assetPath) async {
    const keyBase64 = String.fromEnvironment("ASSET_KEY_BASE64");
    const ivBase64 = String.fromEnvironment("ASSET_IV_BASE64");
    final key = encrypt.Key.fromBase64(keyBase64);
    final iv = encrypt.IV.fromBase64(ivBase64);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    try {
      final assetByteData = await rootBundle.load(assetPath);
      final encryptedBase64 = assetByteData.buffer.asUint8List();
      final decryptedBase64 =
          encrypter.decrypt(encrypt.Encrypted(encryptedBase64), iv: iv);
      final decryptedBytes = base64Decode(decryptedBase64);
      return decryptedBytes;
    } catch (exception) {
      return null;
    }
  }

  Future<Directory> _windowsPictureSaveDirectory(String saveDir) async {
    if (saveDir.isEmpty) {
      return Directory(
        '${(await getApplicationDocumentsDirectory()).path}\\nai-generated',
      );
    }
    return Directory(saveDir);
  }

  String _joinWindowsPath(String directory, String fileName) {
    if (directory.endsWith(r'\') || directory.endsWith('/')) {
      return '$directory$fileName';
    }
    return '$directory\\$fileName';
  }

  Future<bool> _requestAlbumPermission() async {
    bool isGranted;
    if (Platform.isAndroid) {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final deviceInfo = await deviceInfoPlugin.androidInfo;
      final sdkInt = deviceInfo.version.sdkInt;
      isGranted =
          sdkInt < 29 ? await Permission.storage.request().isGranted : true;
    } else {
      isGranted = await Permission.photosAddOnly.request().isGranted;
    }
    return isGranted;
  }
}
