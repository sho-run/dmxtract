// How extractPdf() keeps going when OCR fails. Tesseract reads only the
// pages whose text layer is too thin to use (an image-only cover, a scan)
// plus the detailed table pass, but it used to be all or nothing: a worker
// that failed to start, or one recognize() that threw, ended the whole
// manual with "We could not read that file" even when every table page had
// an exact text layer (ADJ Encore LP12Z IP, whose cover is an image).
//
// Split out from manual_extractor.js (which otherwise pulls in the pdfjs
// import and DOM/canvas calls) so it can be unit tested directly - see
// ocr_guard.test.mjs.

// `startWorker` creates the OCR worker, on the first read that needs it.
// `read(page, fallback, run)` returns `{ value, ocr }`: what `run(worker)`
// gave, or `fallback` when the worker could not start or `run` threw. A
// worker whose start rejects is not tried again, so every later read fails
// at once without calling `run` (a start that never settles still hangs); a
// single failed read leaves the worker in use for the next one.
// `failedPages` lists, in page order, the pages whose latest read failed
// (`page` is null for a read that belongs to no page).
export function ocrGuard(startWorker) {
  let worker = null;
  let unavailable = false;
  const failedPages = new Set();
  const failed = (page, fallback) => {
    if (page !== null) failedPages.add(page);
    return { value: fallback, ocr: false };
  };
  return {
    get worker() {
      return worker;
    },
    get failedPages() {
      return [...failedPages].sort((a, b) => a - b);
    },
    async read(page, fallback, run) {
      if (unavailable) return failed(page, fallback);
      try {
        worker ||= await startWorker();
      } catch {
        unavailable = true;
        return failed(page, fallback);
      }
      try {
        const value = await run(worker);
        if (page !== null) failedPages.delete(page);
        return { value, ocr: true };
      } catch {
        return failed(page, fallback);
      }
    },
  };
}
