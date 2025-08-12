import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Triggers download. Returns null (no filesystem path on web).
Future<String?> saveBytesToDevice(String fileName, List<int> bytes) async {
  // Convert List<int> to Uint8List for correct JS interop.
  final Uint8List uint8list = Uint8List.fromList(bytes);

  // Create a blob from the Uint8List.
  final web.Blob blob = web.Blob(
    [uint8list.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );

  // Create an object URL for the blob.
  final String url = web.URL.createObjectURL(blob);

  // Create a temporary anchor element to trigger the download.
  final web.HTMLAnchorElement a = web.HTMLAnchorElement();
  a.href = url;
  a.download = fileName;

  // Append the anchor element to the body, click it, and then remove it.
  web.document.body?.append(a);
  a.click();
  a.remove();

  // Revoke the object URL to free up resources.
  web.URL.revokeObjectURL(url);

  return null;
}