# DMXtract web

The Flutter web client runs manual extraction entirely in the browser. PDF.js, Tesseract.js, OCR language data, fonts, textures, and the shared Rust/WASM core are all served from `web/` or Flutter assets.

Run `../../scripts/build-wasm.sh` before a release build, then use `flutter run -d chrome` or `flutter build web --release` from this directory.
