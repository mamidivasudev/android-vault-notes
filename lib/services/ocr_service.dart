import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OcrService — picks an image from the camera or gallery and extracts text
/// using Google ML Kit's on-device text recognizer (no internet required).
class OcrService {
  static final _picker = ImagePicker();
  static final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Opens the camera (or gallery), runs OCR, and returns the recognized text.
  /// Returns `null` if the user cancels or no text is found.
  static Future<String?> pickAndRecognize(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (picked == null) return null;

      final inputImage = InputImage.fromFilePath(picked.path);
      final RecognizedText result = await _recognizer.processImage(inputImage);

      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } catch (e) {
      return null;
    }
  }

  /// Clean up recognizer resources
  static void dispose() {
    _recognizer.close();
  }
}
