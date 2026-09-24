import assert from 'node:assert/strict';
import test from 'node:test';

import { detailedOcrPages } from './ocr_pages.js';

// Shaped like the Eliminator Furious Five RG manual's DMX Traits pages, which
// have an exact text layer.
const tablePage = [
  'Eliminator Furious Five RG - DMX Traits',
  '11-CH MODE 24-CH MODE',
  '1   000 - 255   Master Dimmer , 0 to 100%',
  'UV Strobe',
  '2   000 - 007   No strobe',
  '008 - 255   Strobe, slow to fast',
  'UV Dimmer',
  '3   000 - 007   Off',
  '008 - 255   Dimmer, 0% to 100%',
].join('\n');

// The regression this guards: that manual's back cover (page 24) is blank,
// so it alone started the Tesseract worker, and the detailed pass then
// re-read its six table pages anyway and prepended garbled rows to three of
// them - enough to corrupt a table parser that reads the first copy of a
// row it sees.
test('a blank cover page does not send text-layer table pages through OCR', () => {
  const pages = [
    { page: 15, text: tablePage },
    { page: 16, text: tablePage },
    { page: 24, text: '' },
  ];
  assert.deepEqual([...detailedOcrPages(pages, new Set([24]), 24)], []);
});

test('scanned table pages still get the detailed pass', () => {
  const pages = [
    { page: 1, text: 'Cover' },
    { page: 2, text: tablePage },
  ];
  assert.deepEqual([...detailedOcrPages(pages, new Set([1, 2]), 2)], [2]);
});

test('a channel-table heading still pulls in a next page that lacks a readable table', () => {
  const heading = { page: 3, text: '12CH Channel Table\nDMX channels' };
  const scanned = { page: 4, text: 'continued rows' };
  assert.deepEqual([...detailedOcrPages([heading, scanned], new Set([3, 4]), 4)], [3, 4]);
  const readable = { page: 4, text: tablePage };
  assert.deepEqual([...detailedOcrPages([heading, readable], new Set([3]), 4)], [3]);
});

// A text-layer page that names its channel table but prints the rows as an
// image has nothing to read the table from except OCR.
test('a text-layer heading over an image-only table still gets the detailed pass', () => {
  const pages = [
    { page: 1, text: '' },
    { page: 2, text: 'DMX 16CH Channel Table\nSee the chart below for every channel.' },
  ];
  assert.deepEqual([...detailedOcrPages(pages, new Set([1]), 2)], [2]);
});

// A heading page whose own rows read still pulls in the scanned page after
// it, as before; only the heading page itself is left alone.
test('a readable heading page still pulls in a scanned page after it', () => {
  const heading = { page: 1, text: `DMX 12CH Channel Table\n${tablePage}` };
  const scanned = { page: 2, text: 'rows' };
  assert.deepEqual([...detailedOcrPages([heading, scanned], new Set([2]), 2)], [2]);
});
