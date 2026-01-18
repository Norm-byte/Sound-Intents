// Web implementation that uses a native HTML <input type="file"> as fallback.
import 'dart:async';
import 'dart:typed_data';
// ignore: deprecated_member_use
import 'dart:html' as html; // Using dart:html for file input fallback; acceptable until migrated to package:web

class WebPickedFile {
  final String name;
  final Uint8List bytes;
  WebPickedFile(this.name, this.bytes);
}

Future<WebPickedFile?> pickFileViaHtml({String? accept}) async {
  final completer = Completer<WebPickedFile?>();
  final input = html.FileUploadInputElement();
  if (accept != null && accept.isNotEmpty) {
    input.accept = accept; // e.g. .png,.jpg,.jpeg,.gif,.mp3,.wav,.mp4,.webm,.mov
  }
  input.multiple = false;

  input.onChange.listen((event) async {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    final file = files.first;
    final reader = html.FileReader();

    reader.onLoad.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        final bytes = Uint8List.view(result);
        completer.complete(WebPickedFile(file.name, bytes));
      } else if (result is Uint8List) {
        completer.complete(WebPickedFile(file.name, result));
      } else {
        completer.complete(null);
      }
    });
    reader.onError.listen((_) => completer.complete(null));

    reader.readAsArrayBuffer(file);
  });

  // Trigger the dialog
  input.click();

  return completer.future;
}
