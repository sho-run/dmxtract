// Picks the pages that get extractPdf()'s second, high-resolution "read the
// DMX table carefully" OCR pass.
//
// Split out from manual_extractor.js (which otherwise pulls in the pdfjs
// import and DOM/canvas calls) so this selection can be unit tested
// directly - see ocr_pages.test.mjs.
//
// A page whose own text layer already carries its table never qualifies.
// The Tesseract worker starts as soon as any single page has too little text
// layer to read - often nothing more than a blank back cover - and this pass
// used to run over every page with a DMX-looking table once the worker
// existed, prepending its noisier reading ("O00 - O07", "OB4 - 1102 3low
// Pulse", "7   40" for "7   18") ahead of a text layer that was already
// exact. In the local manual corpus that re-read the table pages of 119 of
// 161 PDFs. Pages that were OCR'd, text-layer pages that name a channel
// table without carrying its rows (a table printed as an image), and a page
// short of text after such a heading - even one whose own table reads - are
// still read as before.

export function tableRangeCount(text) {
  return (text.match(/\b\d{1,3}\s*[-–—]\s*\d{1,3}\b/g) || []).length;
}

export function looksLikeDmxTable(text) {
  return /(channel\s+value\s+table|dmx\s+channel\s+assignments(?:\s+and\s+values)?|dmx\s+charts?|dmx\s+traits|dmx\s+channels?|channel\s+dmx\s+function|\b[A-Z]{0,3}\s*\d{1,3}\s*[A-Z]{0,3}\s+channel\s+table\b)/i.test(text);
}

export function tableHeadingCount(text) {
  return (text.match(/\b[A-Z]{0,3}\s*\d{1,3}\s*[A-Z]{0,3}\s+channel\s+table\b/gi) || []).length;
}

// A text layer with at least this many value ranges already holds its
// table; OCR can only add a noisier second copy of it.
const READABLE_TABLE_RANGES = 5;

// `pages` is extractPdf()'s [{ page, text }] list, `ocrPages` the set of page
// numbers whose text came from OCR because their text layer was too thin.
export function detailedOcrPages(pages, ocrPages, pageCount) {
  const byNumber = new Map(pages.map(page => [page.page, page]));
  const unread = number => {
    const page = byNumber.get(number);
    return page !== undefined &&
      (ocrPages.has(number) || tableRangeCount(page.text) < READABLE_TABLE_RANGES);
  };
  const detailed = new Set();
  for (const page of pages) {
    const headings = tableHeadingCount(page.text);
    if (looksLikeDmxTable(page.text) && headings > 0 && headings <= 3) {
      if (unread(page.page)) detailed.add(page.page);
      if (page.page < pageCount && unread(page.page + 1)) detailed.add(page.page + 1);
    }
    if (ocrPages.has(page.page) && tableRangeCount(page.text) >= READABLE_TABLE_RANGES) {
      detailed.add(page.page);
    }
  }
  return detailed;
}
