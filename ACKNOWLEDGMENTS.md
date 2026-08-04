# Acknowledgments

DMXtract is possible because of a broad open-source ecosystem. We are especially
grateful to the maintainers and contributors of these projects:

## Fixture formats and DMX output

- [Open Fixture Library](https://github.com/OpenLightingProject/open-fixture-library)
  provides the open fixture format and validator used to check DMXtract's OFL
  exports. Compatibility is tested against the revision recorded in
  [`schemas/ofl-revision.txt`](schemas/ofl-revision.txt).
- [GDTF](https://github.com/mvrdevelopment/spec) provides the open fixture
  interchange specification targeted by DMXtract's GDTF 1.2 exporter.
- [pyGDTF](https://github.com/open-stage/python-gdtf) provides the canonical
  GDTF 1.2 attribute definitions used by the channel-type editor and an
  independent parser used to test generated GDTF files.
- [Open Lighting Architecture](https://github.com/OpenLightingProject/ola)
  provides the optional macOS DMX transport planned for the native bridge. The
  pinned source and binary-release requirements are recorded in
  [`third_party/ola/README.md`](third_party/ola/README.md).

## Local document processing

- [PDF.js](https://github.com/mozilla/pdf.js) reads PDF text and page geometry
  locally in the browser.
- [Tesseract.js](https://github.com/naptha/tesseract.js) and
  [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) perform local OCR
  for scans and photos.

## Application platform

- [Flutter](https://github.com/flutter/flutter) powers the browser interface.
- [Rust](https://github.com/rust-lang/rust) and
  [wasm-bindgen](https://github.com/wasm-bindgen/wasm-bindgen) let the validation
  and export core run both natively and in the browser.
- [Tauri](https://github.com/tauri-apps/tauri) provides the native tray-app
  shell for the hardware bridge.

DMXtract also depends on many excellent Rust crates and Dart packages. The
authoritative, versioned dependency lists are in [`Cargo.lock`](Cargo.lock) and
[`apps/web/pubspec.lock`](apps/web/pubspec.lock). License obligations for
resources distributed with DMXtract are documented separately in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and `third_party/licenses/`.

Thank you to every maintainer, contributor, standards author, tester, and
lighting technician whose work makes open fixture data more useful.
