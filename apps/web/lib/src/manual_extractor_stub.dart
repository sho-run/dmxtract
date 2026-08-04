import 'dart:typed_data';

class ExtractedManual {
  const ExtractedManual({
    required this.text,
    required this.pageCount,
    this.thumbnails = const [],
  });
  final String text;
  final int pageCount;
  final List<String> thumbnails;
}

Future<ExtractedManual> extractManual(Uint8List bytes, String mime) =>
    throw UnsupportedError('Manual extraction runs in Chrome or Edge.');

Future<String> extractManualRegion(
  Uint8List bytes,
  String mime,
  int page,
  double left,
  double top,
  double width,
  double height,
) => throw UnsupportedError('Manual extraction runs in Chrome or Edge.');
