import assert from 'node:assert/strict';
import test from 'node:test';

import { ocrGuard } from './ocr_guard.js';

// A worker whose recognize() throws for the page numbers listed.
const workerFailingOn = pages => ({
  recognize: async page => {
    if (pages.includes(page)) throw new Error(`page ${page} failed`);
    return `page ${page} as OCR read it`;
  },
});

test('a page whose OCR throws keeps its text layer, and the next page is still read', async () => {
  const ocr = ocrGuard(async () => workerFailingOn([1]));
  assert.deepEqual(await ocr.read(1, 'cover text layer', worker => worker.recognize(1)), {
    value: 'cover text layer',
    ocr: false,
  });
  assert.deepEqual(await ocr.read(2, '', worker => worker.recognize(2)), {
    value: 'page 2 as OCR read it',
    ocr: true,
  });
  assert.deepEqual(ocr.failedPages, [1]);
});

test('a worker that cannot start is tried once, and every page keeps its text layer', async () => {
  let starts = 0;
  let runs = 0;
  const ocr = ocrGuard(async () => {
    starts += 1;
    throw new Error('no OCR worker');
  });
  const run = worker => {
    runs += 1;
    return worker.recognize();
  };
  assert.deepEqual(await ocr.read(1, 'first', run), { value: 'first', ocr: false });
  assert.deepEqual(await ocr.read(2, 'second', run), { value: 'second', ocr: false });
  // The detailed pass still asks for its pages, which are listed too.
  assert.deepEqual(await ocr.read(7, null, run), { value: null, ocr: false });
  assert.equal(starts, 1);
  assert.equal(runs, 0);
  assert.equal(ocr.worker, null);
  assert.deepEqual(ocr.failedPages, [1, 2, 7]);
});

test('the worker starts on first use and is reused', async () => {
  let starts = 0;
  const ocr = ocrGuard(async () => {
    starts += 1;
    return workerFailingOn([]);
  });
  assert.equal(ocr.worker, null);
  await ocr.read(1, '', worker => worker.recognize(1));
  await ocr.read(2, '', worker => worker.recognize(2));
  assert.equal(starts, 1);
  assert.deepEqual(ocr.failedPages, []);
});

test('failed pages are listed once, in page order', async () => {
  const ocr = ocrGuard(async () => workerFailingOn([3, 9, 12]));
  // The detailed pass re-reads pages the first pass read, so a page can fail
  // twice, and it visits them out of page order.
  await ocr.read(9, '', worker => worker.recognize(9));
  await ocr.read(12, '', worker => worker.recognize(12));
  await ocr.read(9, null, worker => worker.recognize(9));
  await ocr.read(3, null, worker => worker.recognize(3));
  assert.deepEqual(ocr.failedPages, [3, 9, 12]);
});

test('a page is no longer listed once a later read of it works', async () => {
  let reads = 0;
  const ocr = ocrGuard(async () => ({
    recognize: async () => {
      reads += 1;
      if (reads === 1) throw new Error('first read failed');
      return 'read on the second try';
    },
  }));
  await ocr.read(2, '', worker => worker.recognize());
  assert.deepEqual(ocr.failedPages, [2]);
  assert.deepEqual(await ocr.read(2, null, worker => worker.recognize()), {
    value: 'read on the second try',
    ocr: true,
  });
  assert.deepEqual(ocr.failedPages, []);
});

test('a failed read that belongs to no page lists no page', async () => {
  const ocr = ocrGuard(async () => ({
    setParameters: async () => {
      throw new Error('parameters rejected');
    },
  }));
  assert.deepEqual(await ocr.read(null, null, worker => worker.setParameters({})), { value: null, ocr: false });
  assert.deepEqual(ocr.failedPages, []);
});
