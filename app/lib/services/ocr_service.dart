import 'dart:convert';
import 'dart:typed_data';
import 'api_client.dart';

/// Module 8, FR-2: text extraction from a product-label photo. The image goes
/// to our backend, which calls the Google Vision API (so the API key never
/// ships inside the app).
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  Future<String> extractText(Uint8List imageBytes) async {
    final body = await ApiClient.instance.send(
      'POST',
      '/api/scan/ocr',
      body: {'imageBase64': base64Encode(imageBytes)},
      timeout: const Duration(seconds: 40),
    );
    return ((body as Map)['text'] as String?) ?? '';
  }
}
