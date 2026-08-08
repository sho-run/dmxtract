import assert from 'node:assert/strict';
import test from 'node:test';

import { wordsFromRecognizeData } from './tesseract_words.js';

test('returns the legacy flat words array unchanged when present', () => {
  const words = [{ text: 'Hello', confidence: 91 }];
  assert.equal(wordsFromRecognizeData({ words }), words);
});

// The regression this guards: the vendored Tesseract.js build's
// recognize() defaults `blocks` to false and never populates a top-level
// `words` array at all — word-level data only exists nested under
// `blocks[].paragraphs[].lines[].words[]` once `blocks: true` is requested.
// Before wordsFromRecognizeData() handled this shape, manual_extractor.js's
// rotation-detection scoring read `data.words` directly, got `undefined`
// every time, and silently scored every rotation candidate as 0 — so
// detectRotation() always kept rotation 0 regardless of a photo's actual
// orientation (verified against two real sideways manual photos in
// testcorpus/, both of which the live site misread as upright).
test('flattens words nested under blocks/paragraphs/lines when data.words is absent', () => {
  const data = {
    blocks: [
      {
        paragraphs: [
          {
            lines: [
              { words: [{ text: '30-channel', confidence: 62 }, { text: 'mode', confidence: 58 }] },
              { words: [{ text: 'Channel', confidence: 71 }] },
            ],
          },
        ],
      },
    ],
  };
  assert.deepEqual(wordsFromRecognizeData(data).map(w => w.text), [
    '30-channel',
    'mode',
    'Channel',
  ]);
});

test('returns an empty list when neither words nor blocks are present', () => {
  assert.deepEqual(wordsFromRecognizeData({}), []);
  assert.deepEqual(wordsFromRecognizeData({ blocks: [] }), []);
  assert.deepEqual(wordsFromRecognizeData({ blocks: [{}] }), []);
});
