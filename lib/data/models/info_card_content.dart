import 'dart:typed_data';

class InfoCardContent {
  final String title;
  final String info;
  final Map<String, dynamic> additionalInfo;
  final String? contentOrderText;

  final Uint8List? imageBytes;
  final String? imagePath;

  const InfoCardContent({
    required this.title,
    required this.info,
    required this.additionalInfo,
    this.contentOrderText,
    this.imageBytes,
    this.imagePath,
  });

  factory InfoCardContent.fromEmpty() => const InfoCardContent(
        title: '',
        info: '',
        additionalInfo: {},
      );
}
