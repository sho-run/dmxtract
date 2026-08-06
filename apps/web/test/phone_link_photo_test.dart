import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dmxtract_web/src/app_state.dart';
import 'package:dmxtract_web/src/phone_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test(
    'a photo received over the phone link enters the same photo set as the file picker',
    () {
      final state = DmxtractState();
      state.addPhotos([
        ManualPhoto(
          bytes: Uint8List.fromList([9, 9, 9]),
          name: 'picked.jpg',
          mime: 'image/jpeg',
        ),
      ]);

      state.receivePhoneLinkPhoto(
        ReceivedPhoto(
          'phone-1.jpg',
          'image/jpeg',
          Uint8List.fromList([1, 2, 3]),
        ),
      );
      expect(state.photos.map((photo) => photo.name), [
        'picked.jpg',
        'phone-1.jpg',
      ]);

      // A retried chunk delivering the same photo twice is deduplicated
      // exactly like a duplicate file-picker selection.
      state.receivePhoneLinkPhoto(
        ReceivedPhoto(
          'phone-1.jpg',
          'image/jpeg',
          Uint8List.fromList([1, 2, 3]),
        ),
      );
      expect(state.photos.length, 2);

      // Phone photos join the same reorder/remove operations as any other
      // queued photo, then flow into readPhotos() identically.
      state.movePhoto(1, -1);
      expect(state.photos.map((photo) => photo.name), [
        'phone-1.jpg',
        'picked.jpg',
      ]);

      state.dispose();
    },
  );
}
