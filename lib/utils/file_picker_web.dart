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

  // Important for Safari/macOS: The input must be in the DOM to trigger a click
  uploadInput.style.display = 'none';
  html.document.body?.append(uploadInput);

  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      uploadInput.remove();
      return;
    }

    final file = files[0];
    final reader = html.FileReader();
    reader.readAsDataUrl(file);

    reader.onLoadEnd.listen((e) {
      final result = reader.result as String;
      final base64String = result.split(',').last;
      completer.complete(PickedFileData(
        filename: file.name,
        base64String: base64String,
      ));
      uploadInput.remove();
    });
  });

  uploadInput.click();

  return completer.future;
}

Future<void> saveFileBytes(Uint8List bytes, String filename) async {
  String mimeType = 'application/octet-stream';
  final lowerName = filename.toLowerCase();
  if (lowerName.endsWith('.pdf'))
    mimeType = 'application/pdf';
  else if (lowerName.endsWith('.zip'))
    mimeType = 'application/zip';
  else if (lowerName.endsWith('.xlsx'))
    mimeType =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  else if (lowerName.endsWith('.xls'))
    mimeType = 'application/vnd.ms-excel';
  else if (lowerName.endsWith('.csv')) mimeType = 'text/csv';

  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute("download", filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
