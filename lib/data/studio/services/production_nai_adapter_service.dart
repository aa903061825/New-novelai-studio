import 'dart:convert';
import 'dart:typed_data';

import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/services/api_service.dart';
import 'package:nai_casrand/data/services/file_service.dart';
import 'package:nai_casrand/data/services/image_service.dart';

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
    String productionPlanId,
    String? outputDirectoryOverride,
  ) async {
    final effectiveOutputDirectory = outputDirectoryOverride ?? outputDirectory;
    if (effectiveOutputDirectory.trim().isNotEmpty) {
      await savePictureToFile(bytes, fileName, effectiveOutputDirectory);
      return resolvePictureSavePath(fileName, effectiveOutputDirectory);
    }
    final scopedFileName =
        '${_safePathSegment(productionPlanId)}/${_safeFileName(fileName)}';
    await savePictureToFile(bytes, scopedFileName, effectiveOutputDirectory);
    return resolvePictureSavePath(scopedFileName, effectiveOutputDirectory);
  }
}

String _safePathSegment(String value) {
  final sanitized = value
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return sanitized.isEmpty ? 'production-plan' : sanitized;
}

String _safeFileName(String value) {
  final normalized = value.trim().replaceAll('\\', '/').split('/').last;
  return _safePathSegment(normalized);
}

String _apiErrorMessage(Uint8List data) {
  try {
    return utf8.decode(data);
  } catch (_) {
    return '${data.length} response bytes';
  }
}
