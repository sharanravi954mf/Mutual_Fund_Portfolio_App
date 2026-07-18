import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class PickedFileData {
  final String filename;
  final Uint8List? bytes;
  final String? base64String;

  PickedFileData({required this.filename, this.bytes, this.base64String});
}

Future<PickedFileData?> pickFile(String accept) async {
  final completer = Completer<PickedFileData?>();
  final uploadInput = html.FileUploadInputElement()..accept = accept;
  uploadInput.click();

  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    
    final file = files[0];
    final reader = html.FileReader();
    reader.readAsDataURL(file);
    
    reader.onLoadEnd.listen((e) {
      final result = reader.result as String;
      final base64String = result.split(',').last;
      completer.complete(PickedFileData(
        filename: file.name,
        base64String: base64String,
      ));
    });
  });

  return completer.future;
}

Future<void> saveFileBytes(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute("download", filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
