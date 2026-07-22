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
  final List<String> allowed = [];
  final acceptLower = accept.toLowerCase();
  if (acceptLower.contains('.pdf')) allowed.add('pdf');
  if (acceptLower.contains('.zip')) allowed.add('zip');
  if (acceptLower.contains('.xlsx')) allowed.add('xlsx');
  if (acceptLower.contains('.xls')) allowed.add('xls');
  if (acceptLower.contains('.csv')) allowed.add('csv');
  if (acceptLower.contains('.png')) allowed.add('png');
  if (acceptLower.contains('.jpg') || acceptLower.contains('.jpeg')) {
    allowed.addAll(['jpg', 'jpeg']);
  }
  if (allowed.isEmpty) {
    allowed.addAll(['pdf', 'zip', 'xlsx', 'xls', 'csv', 'png', 'jpg', 'jpeg']);
  }

  final isImageOnly = (allowed.contains('png') ||
          allowed.contains('jpg') ||
          allowed.contains('jpeg')) &&
      allowed.every((ext) => ['png', 'jpg', 'jpeg'].contains(ext));

  final result = await fp.FilePicker.platform.pickFiles(
    type: isImageOnly ? fp.FileType.image : fp.FileType.custom,
    allowedExtensions: isImageOnly ? null : allowed,
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
