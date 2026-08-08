// Derives a flat per-word list from a Tesseract.js recognize() result's
// `data` object.
//
// Split out from manual_extractor.js (which otherwise pulls in the pdfjs
// import and DOM/canvas calls) so this pure, DOM-free piece of logic can be
// unit tested directly — see tesseract_words.test.mjs.
//
// Why this exists: the vendored Tesseract.js build defaults recognize()'s
// `blocks` output flag to false. tesseract.js@5.1.1 (used to calibrate the
// rotation-detection thresholds in manual_extractor.js against the photos
// in testcorpus/) defaults `blocks` to true and, when blocks are present,
// also flattens them into top-level `words`/`lines`/`paragraphs` arrays for
// convenience. The vendored build does neither by default: request
// `blocks: true` explicitly, then walk the block/paragraph/line hierarchy
// yourself — `data.words` is simply `undefined` otherwise, which silently
// degrades to an empty list through `|| []` and zeroes every OCR-confidence
// score derived from it (this broke rotation detection outright: every
// candidate tied at a score of 0, so detectRotation() always kept the
// first/untried candidate — rotation 0 — no matter the photo's actual
// orientation).
export function wordsFromRecognizeData(data) {
  if (Array.isArray(data.words)) return data.words;
  const words = [];
  for (const block of data.blocks || []) {
    for (const paragraph of block.paragraphs || []) {
      for (const line of paragraph.lines || []) {
        for (const word of line.words || []) words.push(word);
      }
    }
  }
  return words;
}
