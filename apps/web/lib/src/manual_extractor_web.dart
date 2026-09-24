import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('dmxtract.extractManual')
external JSPromise<JSString> _extractManual(JSUint8Array bytes, JSString mime);

@JS('dmxtract.extractManualRegion')
external JSPromise<JSString> _extractManualRegion(
  JSUint8Array bytes,
  JSString mime,
  JSNumber page,
  JSNumber left,
  JSNumber top,
  JSNumber width,
  JSNumber height,
  JSNumber rotation,
);

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

  /// The clockwise rotation (0/90/180/270) manual_extractor.js's
  /// content-based orientation detector applied to each page before OCR —
  /// only ever non-zero for photo sources, never PDFs. A region re-read
  /// (extractManualRegion) must rotate its own source render by the same
  /// amount, or the box the user drew over the (rotated) thumbnail lands on
  /// the wrong pixels of the (unrotated) original.
  final List<int> rotations;

  /// The pages (1-based, in page order) whose latest OCR read in
  /// manual_extractor.js failed, on the first read or the detailed table
  /// pass. A page keeps what it had before that read: its text layer, often
  /// empty, or its first read's OCR. Anything printed only there may be
  /// missing.
  final List<int> ocrFailedPages;
}

Future<ExtractedManual> extractManual(Uint8List bytes, String mime) async {
  final raw = (await _extractManual(bytes.toJS, mime.toJS).toDart).toDart;
  final json = jsonDecode(raw) as Map<String, Object?>;
  final pages = json['pages'] as List;
  return ExtractedManual(
    text: pages
        .map((page) {
          final item = page as Map;
          return '=== DMXTRACT PAGE ${item['page']} ===\n${item['text'] as String? ?? ''}';
        })
        .join('\n\n'),
    pageCount: json['pageCount'] as int? ?? pages.length,
    thumbnails: (json['thumbnails'] as List? ?? []).cast<String>(),
    rotations: pages
        .map((page) => (page as Map)['rotation'] as int? ?? 0)
        .toList(),
    ocrFailedPages: [
      for (final page in json['ocrFailedPages'] as List? ?? const [])
        page as int,
    ],
  );
}

Future<String> extractManualRegion(
  Uint8List bytes,
  String mime,
  int page,
  double left,
  double top,
  double width,
  double height,
  int rotation,
) async => (await _extractManualRegion(
  bytes.toJS,
  mime.toJS,
  page.toJS,
  left.toJS,
  top.toJS,
  width.toJS,
  height.toJS,
  rotation.toJS,
).toDart).toDart;
