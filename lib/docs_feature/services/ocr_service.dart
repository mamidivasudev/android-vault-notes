import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  static final _picker = ImagePicker();
  static final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

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
      print('OCR Error: $e');
      return null;
    }
  }
}
