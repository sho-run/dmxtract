import 'dart:typed_data';

class ExtractedManual {
  const ExtractedManual({
    required this.text,
    required this.pageCount,
    this.thumbnails = const [],
    this.rotations = const [],
    this.ocrFailedPages = const [],
  });
  final String text;
  final int pageCount;
  final List<String> thumbnails;
  final List<int> rotations;
  final List<int> ocrFailedPages;
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
  int rotation,
) => throw UnsupportedError('Manual extraction runs in Chrome or Edge.');
