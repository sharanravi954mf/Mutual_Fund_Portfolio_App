import 'dart:typed_data';

class PickedFileData {
  final String filename;
  final Uint8List? bytes;
  final String? base64String;

  PickedFileData({required this.filename, this.bytes, this.base64String});
}

Future<PickedFileData?> pickFile(String accept) async {
  throw UnimplementedError("Platform not supported");
}

Future<void> saveFileBytes(Uint8List bytes, String filename) async {
  throw UnimplementedError("Platform not supported");
}
