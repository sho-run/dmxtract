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
);

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

Future<ExtractedManual> extractManual(Uint8List bytes, String mime) async {
  final raw = (await _extractManual(bytes.toJS, mime.toJS).toDart).toDart;
  final json = jsonDecode(raw) as Map<String, Object?>;
  final pages = json['pages'] as List;
  return ExtractedManual(
    text: pages
        .map((page) => (page as Map)['text'] as String? ?? '')
        .join('\n\n'),
    pageCount: json['pageCount'] as int? ?? pages.length,
    thumbnails: (json['thumbnails'] as List? ?? []).cast<String>(),
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
) async => (await _extractManualRegion(
  bytes.toJS,
  mime.toJS,
  page.toJS,
  left.toJS,
  top.toJS,
  width.toJS,
  height.toJS,
).toDart).toDart;
