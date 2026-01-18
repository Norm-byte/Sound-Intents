import 'dart:typed_data';

// Stub implementation used on non-web platforms.
class WebPickedFile {
  final String name;
  final Uint8List bytes;
  WebPickedFile(this.name, this.bytes);
}

Future<WebPickedFile?> pickFileViaHtml({String? accept}) async {
  // Non-web: let the regular FilePicker handle things; return null here.
  return null;
}
