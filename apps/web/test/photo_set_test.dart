import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dmxtract_web/src/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('photo set appends, deduplicates, reorders, and removes locally', () {
    final state = DmxtractState();
    final first = ManualPhoto(
      bytes: Uint8List.fromList([1, 2, 3]),
      name: 'page-1.jpg',
      mime: 'image/jpeg',
    );
    final second = ManualPhoto(
      bytes: Uint8List.fromList([4, 5, 6, 7]),
      name: 'page-2.jpg',
      mime: 'image/jpeg',
    );

    state.addPhotos([first, second, first]);
    expect(state.photos.map((photo) => photo.name), [
      'page-1.jpg',
      'page-2.jpg',
    ]);

    state.movePhoto(1, -1);
    expect(state.photos.map((photo) => photo.name), [
      'page-2.jpg',
      'page-1.jpg',
    ]);

    state.removePhoto(0);
    expect(state.photos.single.name, 'page-1.jpg');

    state.clearPhotos();
    expect(state.photos, isEmpty);
    state.dispose();
  });
}
