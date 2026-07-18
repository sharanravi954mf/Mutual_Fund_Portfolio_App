import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart' as fp;

class PickedFileData {
  final String filename;
  final Uint8List? bytes;
  final String? base64String;

  PickedFileData({required this.filename, this.bytes, this.base64String});
}

Future<PickedFileData?> pickFile(String accept) async {
  final type = accept == '.pdf' ? fp.FileType.custom : fp.FileType.image;
  final allowedExtensions = accept == '.pdf' ? ['pdf'] : ['png', 'jpg', 'jpeg'];
  
  final result = await fp.FilePicker.platform.pickFiles(
    type: type,
    allowedExtensions: allowedExtensions,
    withData: true,
  );

  if (result != null && result.files.isNotEmpty) {
    final file = result.files.first;
    if (file.bytes != null) {
      final base64String = base64.encode(file.bytes!);
      return PickedFileData(
        filename: file.name,
        bytes: file.bytes,
        base64String: base64String,
      );
    }
  }
  return null;
}

Future<void> saveFileBytes(Uint8List bytes, String filename) async {
  // Mobile platform placeholder compilation
  print("Saving file on mobile: $filename");
}
