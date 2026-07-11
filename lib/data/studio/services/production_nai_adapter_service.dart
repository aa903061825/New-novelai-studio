import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/services/api_service.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/services/image_service.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/script_exhibition_image_organizer_service.dart';

typedef ProductionNaiFetch = Future<ApiResponse> Function(ApiRequest request);
typedef ProductionNaiProcessResponse = Uint8List Function(Uint8List bytes);
typedef ProductionNaiSavePicture = Future<void> Function(
  Uint8List bytes,
  String fileName,
  String saveDir,
);
typedef ProductionNaiResolvePicturePath = Future<String> Function(
  String fileName,
  String saveDir,
);

class ProductionNaiApiException implements Exception {
  final int statusCode;
  final String message;

  const ProductionNaiApiException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => 'ProductionNaiApiException($statusCode): $message';
}

class ProductionNaiAdapterService {
  final String endpoint;
  final String proxy;
  final Map<String, String> headers;
  final String outputDirectory;
  final ProductionNaiFetch fetchData;
  final ProductionNaiProcessResponse processResponse;
  final ProductionNaiSavePicture savePictureToFile;
  final ProductionNaiResolvePicturePath resolvePictureSavePath;

  ProductionNaiAdapterService({
    required this.endpoint,
    required this.proxy,
    required this.headers,
    required this.outputDirectory,
    ProductionNaiFetch? fetchData,
    ProductionNaiProcessResponse? processResponse,
    ProductionNaiSavePicture? savePictureToFile,
    ProductionNaiResolvePicturePath? resolvePictureSavePath,
    ApiService? apiService,
    ImageService? imageService,
    FileService? fileService,
  })  : fetchData = fetchData ?? (apiService ?? ApiService()).fetchData,
        processResponse =
            processResponse ?? (imageService ?? ImageService()).processResponse,
        savePictureToFile = savePictureToFile ??
            (fileService ?? FileService()).savePictureToFile,
        resolvePictureSavePath = resolvePictureSavePath ??
            (fileService ?? FileService()).resolvePictureSavePath;

  Future<Uint8List> requestImage(Map<String, dynamic> payload) async {
    final response = await fetchData(
      ApiRequest(
        endpoint: endpoint,
        proxy: proxy,
        headers: headers,
        payload: payload,
      ),
    );
    final statusCode = int.tryParse(response.status) ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw ProductionNaiApiException(
        statusCode: statusCode,
        message: _apiErrorMessage(response.data),
      );
    }
    return processResponse(response.data);
  }

  Future<String> saveImage(Uint8List bytes, String fileName) async {
    await savePictureToFile(bytes, fileName, outputDirectory);
    return resolvePictureSavePath(fileName, outputDirectory);
  }

  Future<String> savePlanImage(
    Uint8List bytes,
    String fileName,
    ProductionPlan plan,
    ProductionTask task,
  ) {
    if (task.taskType == ProductionTaskType.scriptRecastFrame) {
      return saveScriptRecastImage(bytes, plan, task);
    }
    return saveImage(bytes, fileName);
  }

  Future<String> saveScriptRecastImage(
    Uint8List bytes,
    ProductionPlan plan,
    ProductionTask task,
  ) async {
    final effectiveOutputDirectory =
        plan.executionSettings?.outputDirectory.trim().isNotEmpty == true
            ? plan.executionSettings!.outputDirectory
            : outputDirectory;
    final destinationOutputRoot =
        await _scriptRecastDestinationOutputRoot(effectiveOutputDirectory);
    final destination = ScriptExhibitionImagePathPolicy.destinationForTask(
      outputRoot: destinationOutputRoot,
      planName: plan.name,
      task: task,
      existingDestinationKeys: const {},
    );
    final root = Directory(destinationOutputRoot).absolute.path;
    final relativePath = _relativePathUnderRoot(destination, root);
    await savePictureToFile(bytes, relativePath, effectiveOutputDirectory);
    return resolvePictureSavePath(relativePath, effectiveOutputDirectory);
  }

  Future<String> _scriptRecastDestinationOutputRoot(String saveDir) async {
    if (saveDir.trim().isNotEmpty) {
      return saveDir;
    }
    final probePath = await resolvePictureSavePath(
      '__script_exhibition_root_probe__.png',
      saveDir,
    );
    return File(probePath).parent.path;
  }
}

String _relativePathUnderRoot(String path, String root) {
  final pathKey = File(path).absolute.path.replaceAll('\\', '/');
  final rootKey = Directory(root).absolute.path.replaceAll('\\', '/');
  if (pathKey == rootKey || !pathKey.startsWith('$rootKey/')) {
    return path.split(RegExp(r'[\\/]')).last;
  }
  return pathKey
      .substring(rootKey.length + 1)
      .replaceAll('/', Platform.pathSeparator);
}

String _apiErrorMessage(Uint8List data) {
  try {
    return utf8.decode(data);
  } catch (_) {
    return '${data.length} response bytes';
  }
}
