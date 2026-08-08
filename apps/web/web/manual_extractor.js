import * as pdfjs from './vendor/pdfjs/pdf.min.mjs';

pdfjs.GlobalWorkerOptions.workerSrc = './vendor/pdfjs/pdf.worker.min.mjs';

function announce(stage, page, pages) {
  window.dispatchEvent(new CustomEvent('dmxtract-progress', { detail: { stage, page, pages } }));
}

// iPhones shoot HEIC by default and Chrome cannot decode it via
// createImageBitmap. The wasm HEIC decoder (vendor/heic/, ~1.1MB) is never
// fetched on page load — only sniffHeicBytes() runs eagerly (a few dozen
// bytes of arithmetic), and the decoder itself is loaded lazily the first
// time a HEIC photo actually needs decoding. See THIRD_PARTY_NOTICES.md for
// the licensing note (libheif-js, LGPL-3.0, used unmodified).
const HEIC_FTYP_BRANDS = new Set([
  'heic', 'heix', 'heim', 'heis', 'hevc', 'hevx', 'hevm', 'hevs', 'mif1', 'msf1',
]);

// Sniff the ISO-BMFF 'ftyp' box rather than trusting the mime string: photos
// forwarded from the phone hand-off (phone/phone.js) or picked from a file
// input can arrive as 'application/octet-stream' regardless of their actual
// content, and Chrome does not normalize HEIC mime types consistently.
function sniffHeicBytes(bytes) {
  if (!bytes || bytes.length < 12) return false;
  const tag = offset => String.fromCharCode(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]);
  if (tag(4) !== 'ftyp') return false;
  const boxSize = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  // The ftyp box is always small in practice; cap the scan so a malformed
  // or unrelated file with a stray 'ftyp' tag can't force a long loop.
  const limit = Math.min(bytes.length, boxSize > 0 ? boxSize : bytes.length, 512);
  const brands = new Set([tag(8)]);
  for (let offset = 16; offset + 4 <= limit; offset += 4) brands.add(tag(offset));
  for (const brand of brands) if (HEIC_FTYP_BRANDS.has(brand)) return true;
  return false;
}

let heifModulePromise = null;

function loadHeifDecoderScript() {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    // Classic (non-module) script, matching how vendor/tesseract/tesseract.min.js
    // is loaded: libheif-js's wasm build is UMD and only exposes the global
    // `libheif` it needs when it is not evaluated as an ES module.
    script.src = './vendor/heic/libheif.js';
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Could not load the HEIC decoder.'));
    document.head.appendChild(script);
  });
}

async function heifModule() {
  if (!heifModulePromise) {
    heifModulePromise = (async () => {
      if (!window.libheif) await loadHeifDecoderScript();
      // The emscripten glue's default wasm loader falls back to a synchronous
      // XHR, which Chrome refuses to compile on the main thread once the
      // module is more than a few KB ("sync fetching of the wasm failed").
      // Fetching the bytes ourselves and handing them over as `wasmBinary`
      // keeps instantiation on the async (streaming-compile-eligible) path.
      const wasmResponse = await fetch('./vendor/heic/libheif.wasm');
      if (!wasmResponse.ok) throw new Error('Could not load the HEIC decoder.');
      const wasmBinary = new Uint8Array(await wasmResponse.arrayBuffer());
      const factory = window.libheif;
      const instance = factory({ wasmBinary, locateFile: path => `./vendor/heic/${path}` });
      return (instance && typeof instance.then === 'function') ? await instance : instance;
    })();
  }
  return heifModulePromise;
}

async function decodeHeicToCanvas(bytes) {
  const libheif = await heifModule();
  const decoder = new libheif.HeifDecoder();
  const images = decoder.decode(bytes);
  if (!images || !images.length) throw new Error('This HEIC photo has no readable image data.');
  const image = images[0];
  const width = image.get_width();
  const height = image.get_height();
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d');
  const imageData = context.createImageData(width, height);
  await new Promise((resolve, reject) => {
    image.display(imageData, displayData => {
      if (!displayData) { reject(new Error('This HEIC photo could not be decoded.')); return; }
      resolve();
    });
  });
  context.putImageData(imageData, 0, 0);
  return canvas;
}

// Decode photo bytes to a canvas, trying the browser's native decoder first
// (fast path for JPEG/PNG/WebP/etc, including EXIF-orientation handling)
// and falling back to the vendored HEIC decoder only when createImageBitmap
// fails AND the bytes actually sniff as HEIC. `wantPreviewUrl` lets callers
// skip creating an object URL they will not use (see renderSourcePage).
async function decodeImageBytes(bytes, mime, { wantPreviewUrl = true } = {}) {
  const blob = new Blob([bytes], { type: mime });
  let bitmap;
  try {
    bitmap = await createImageBitmap(blob);
  } catch (error) {
    if (!sniffHeicBytes(bytes)) {
      throw new Error(
        `This browser could not decode the photo (${mime || 'unknown format'}). ` +
          'HEIC photos are not supported yet — please retake or export as JPEG or PNG.',
      );
    }
    try {
      const canvas = await decodeHeicToCanvas(bytes);
      // HEIC decodes to a canvas directly; there is no browser-renderable
      // blob URL for it (Chrome cannot put HEIC bytes in an <img>), so the
      // caller must always build its preview from this canvas.
      return { canvas, previewUrl: null };
    } catch (heicError) {
      throw new Error(
        'This HEIC photo could not be decoded. It may be corrupted or use an ' +
          'unsupported HEIC variant — please retake or export as JPEG or PNG.',
      );
    }
  }
  const canvas = document.createElement('canvas');
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  canvas.getContext('2d').drawImage(bitmap, 0, 0);
  bitmap.close();
  return { canvas, previewUrl: wantPreviewUrl ? URL.createObjectURL(blob) : null };
}

async function ocrWorker() {
  return window.Tesseract.createWorker('eng', 1, {
    workerPath: './vendor/tesseract/worker.min.js',
    corePath: './vendor/tesseract/core',
    langPath: './vendor/tesseract/lang',
    logger: message => {
      if (message.status) announce(message.status, Math.round((message.progress || 0) * 100), 100);
    },
  });
}

async function canvasToThumbnail(canvas) {
  const target = document.createElement('canvas');
  const ratio = Math.min(1, 220 / canvas.width);
  target.width = Math.round(canvas.width * ratio);
  target.height = Math.round(canvas.height * ratio);
  target.getContext('2d').drawImage(canvas, 0, 0, target.width, target.height);
  return target.toDataURL('image/jpeg', 0.72);
}

function positionedText(content) {
  const items = content.items
    .filter(item => item.str && item.str.trim() && Array.isArray(item.transform))
    .map(item => ({
      text: item.str.trim(),
      x: item.transform[4],
      y: item.transform[5],
      width: item.width || 0,
      height: Math.abs(item.height || item.transform[3] || 10),
    }))
    .sort((a, b) => Math.abs(a.y - b.y) > 1.5 ? b.y - a.y : a.x - b.x);
  const rows = [];
  for (const item of items) {
    const tolerance = Math.max(2, Math.min(5, item.height * 0.38));
    let row = rows.find(candidate => Math.abs(candidate.y - item.y) <= tolerance);
    if (!row) {
      row = { y: item.y, items: [] };
      rows.push(row);
    }
    row.items.push(item);
  }
  rows.sort((a, b) => b.y - a.y);
  return rows.map(row => {
    row.items.sort((a, b) => a.x - b.x);
    let text = '';
    let right = null;
    for (const item of row.items) {
      const gap = right == null ? 0 : item.x - right;
      text += right == null ? '' : gap > 18 ? '   ' : ' ';
      text += item.text;
      right = Math.max(right ?? item.x, item.x + item.width);
    }
    return text.trim();
  }).filter(Boolean).join('\n');
}

function positionedOcr(tsv) {
  if (!tsv) return '';
  const words = tsv.split(/\r?\n/).slice(1).map(line => {
    const columns = line.split('\t');
    if (columns.length < 12 || columns[0] !== '5') return null;
    const text = columns.slice(11).join('\t').trim();
    if (!text) return null;
    return {
      text,
      x: Number(columns[6]),
      y: Number(columns[7]),
      width: Number(columns[8]),
      height: Number(columns[9]),
    };
  }).filter(Boolean).sort((a, b) => {
    const aCenter = a.y + a.height / 2;
    const bCenter = b.y + b.height / 2;
    return Math.abs(aCenter - bCenter) > 4 ? aCenter - bCenter : a.x - b.x;
  });
  const rows = [];
  for (const word of words) {
    const center = word.y + word.height / 2;
    const tolerance = Math.max(4, Math.min(12, word.height * 0.55));
    let row = rows.find(candidate => Math.abs(candidate.center - center) <= tolerance);
    if (!row) {
      row = { center, words: [] };
      rows.push(row);
    }
    row.words.push(word);
  }
  rows.sort((a, b) => a.center - b.center);
  return rows.map(row => {
    row.words.sort((a, b) => a.x - b.x);
    let text = '';
    let right = null;
    for (const word of row.words) {
      const gap = right == null ? 0 : word.x - right;
      text += right == null ? '' : gap > Math.max(24, word.height * 2) ? '   ' : ' ';
      text += word.text;
      right = Math.max(right ?? word.x, word.x + word.width);
    }
    return text.trim();
  }).filter(Boolean).join('\n');
}

function removeTableLines(canvas) {
  const cleaned = document.createElement('canvas');
  cleaned.width = canvas.width;
  cleaned.height = canvas.height;
  const context = cleaned.getContext('2d', { willReadFrequently: true });
  context.drawImage(canvas, 0, 0);
  const image = context.getImageData(0, 0, cleaned.width, cleaned.height);
  const pixels = image.data;
  const rowInk = new Uint32Array(cleaned.height);
  const columnInk = new Uint32Array(cleaned.width);
  for (let y = 0; y < cleaned.height; y += 1) {
    for (let x = 0; x < cleaned.width; x += 1) {
      const offset = (y * cleaned.width + x) * 4;
      const gray = pixels[offset] * 0.299 + pixels[offset + 1] * 0.587 + pixels[offset + 2] * 0.114;
      const ink = gray < 178;
      const value = ink ? 0 : 255;
      pixels[offset] = value;
      pixels[offset + 1] = value;
      pixels[offset + 2] = value;
      if (ink) { rowInk[y] += 1; columnInk[x] += 1; }
    }
  }
  const rows = new Set();
  const columns = new Set();
  rowInk.forEach((count, y) => { if (count > cleaned.width * 0.42) for (let n = Math.max(0, y - 1); n <= Math.min(cleaned.height - 1, y + 1); n += 1) rows.add(n); });
  columnInk.forEach((count, x) => { if (count > cleaned.height * 0.28) for (let n = Math.max(0, x - 1); n <= Math.min(cleaned.width - 1, x + 1); n += 1) columns.add(n); });
  for (const y of rows) for (let x = 0; x < cleaned.width; x += 1) { const offset = (y * cleaned.width + x) * 4; pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = 255; }
  for (const x of columns) for (let y = 0; y < cleaned.height; y += 1) { const offset = (y * cleaned.width + x) * 4; pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = 255; }
  context.putImageData(image, 0, 0);
  return cleaned;
}

function downscaleCanvas(source, maxSide) {
  const longest = Math.max(source.width, source.height);
  if (longest <= maxSide) return source;
  const ratio = maxSide / longest;
  const scaled = document.createElement('canvas');
  scaled.width = Math.round(source.width * ratio);
  scaled.height = Math.round(source.height * ratio);
  scaled.getContext('2d').drawImage(source, 0, 0, scaled.width, scaled.height);
  return scaled;
}

function rotateCanvas(source, degrees) {
  if (degrees === 0) return source;
  const swapped = degrees === 90 || degrees === 270;
  const rotated = document.createElement('canvas');
  rotated.width = swapped ? source.height : source.width;
  rotated.height = swapped ? source.width : source.height;
  const context = rotated.getContext('2d');
  context.translate(rotated.width / 2, rotated.height / 2);
  context.rotate(degrees * Math.PI / 180);
  context.drawImage(source, -source.width / 2, -source.height / 2);
  return rotated;
}

// Score = sum of per-word OCR confidence (equivalently: mean confidence
// weighted by word count). A photo at the wrong orientation typically yields
// both fewer recognizable words AND lower per-word confidence than the same
// photo upright, so summing rewards both signals and discriminates far more
// reliably than mean confidence alone (which a rotation with 3 lucky-guess
// words can win on) or word count alone (which noise-prone rotations can
// pad with short garbage tokens). The recognized text is kept too: on a
// typical phone photo (much higher resolution than the table actually
// needs) this downscaled trial pass can read *better* than the full-size
// pass that follows it, so the caller gets the option to keep it.
async function quickOrientationScore(worker, canvas) {
  const result = await worker.recognize(canvas);
  const words = (result.data.words || []).filter(word => word.text && word.text.trim());
  const totalConfidence = words.reduce((sum, word) => sum + (word.confidence || 0), 0);
  return {
    score: totalConfidence,
    wordCount: words.length,
    meanConfidence: words.length ? totalConfidence / words.length : 0,
    text: result.data.text || '',
  };
}

const ORIENTATION_TRIAL_MAX_SIDE = 1200;
const ORIENTATION_CONFIRM_MAX_SIDE = 2400;
const ORIENTATION_DECISIVE_WORD_COUNT = 20;
// Calibrated against the real-photo corpus in testcorpus/: upright photos
// scored 66% mean confidence at this trial size, sideways ones scored 24-41%
// read at the wrong (0-degree) orientation — 58 sits with clear margin on
// both sides, so upright photos actually take the fast path they are meant
// to (the old 80 bar sat above every upright photo measured, so the "skip
// the extra trials" branch never fired on this corpus).
const ORIENTATION_DECISIVE_CONFIDENCE = 58;
// If the best and second-best rotation scores are within this fraction of
// each other, the 1200px trial isn't a reliable tiebreaker (measured margin
// on real sideways photos was as low as 16%) — re-score just those two
// candidates at a higher resolution rather than commit to a near coin flip.
const ORIENTATION_MARGIN_RATIO = 0.25;

// Detect a physically sideways/upside-down page by content, not EXIF:
// createImageBitmap already applies EXIF orientation (camera tilt), but a
// manual page photographed while lying sideways on a table carries no EXIF
// signal at all. Try all 4 rotations at low resolution, score each with a
// quick OCR pass, and keep the best. Skip the trial entirely when the
// unrotated pass already scores decisively well, so upright photos (the
// common case) pay no extra OCR cost.
async function detectRotation(worker, canvas) {
  const trialBase = downscaleCanvas(canvas, ORIENTATION_TRIAL_MAX_SIDE);
  const zeroTrial = await quickOrientationScore(worker, trialBase);
  const candidates = [{ rotation: 0, ...zeroTrial }];
  const decisive = zeroTrial.wordCount >= ORIENTATION_DECISIVE_WORD_COUNT
    && zeroTrial.meanConfidence >= ORIENTATION_DECISIVE_CONFIDENCE;
  if (!decisive) {
    for (const degrees of [90, 180, 270]) {
      candidates.push({
        rotation: degrees,
        ...(await quickOrientationScore(worker, rotateCanvas(trialBase, degrees))),
      });
    }
  }
  candidates.sort((a, b) => b.score - a.score);
  let best = candidates[0];
  const runnerUp = candidates[1];
  if (runnerUp && best.score > 0
    && (best.score - runnerUp.score) / best.score < ORIENTATION_MARGIN_RATIO) {
    const confirmBase = downscaleCanvas(canvas, ORIENTATION_CONFIRM_MAX_SIDE);
    const rescored = [];
    for (const candidate of [best, runnerUp]) {
      rescored.push({
        rotation: candidate.rotation,
        ...(await quickOrientationScore(worker, rotateCanvas(confirmBase, candidate.rotation))),
      });
    }
    best = rescored[0].score >= rescored[1].score ? rescored[0] : rescored[1];
  }
  return best;
}

function tableTextScore(text) {
  const normalized = text.replace(/^[\s|[\]{}()_~=—–-]+/gm, '');
  const heading = /(?:channel\s+table|dmx\s+(?:charts?|traits|channels?))/i.test(normalized) ? 500 : 0;
  const rows = (normalized.match(/^\s*\d{1,3}\s+(?:\d{1,3}\s*[-–—._~]\s*\d{1,3}|[A-Za-z])/gm) || []).length;
  const ranges = (text.match(/\b\d{1,3}\s*[-–—]\s*\d{1,3}\b/g) || []).length;
  return heading + rows * 25 + ranges * 8 + Math.min(text.length, 12000) / 100;
}

function tableRowCount(text) {
  return (text.match(/^\s*\d{1,3}\s+(?:\d{1,3}\s*[-–—]\s*\d{1,3}|[A-Za-z])/gm) || []).length;
}

function tableRangeCount(text) {
  return (text.match(/\b\d{1,3}\s*[-–—]\s*\d{1,3}\b/g) || []).length;
}

function looksLikeDmxTable(text) {
  return /(channel\s+value\s+table|dmx\s+channel\s+assignments(?:\s+and\s+values)?|dmx\s+charts?|dmx\s+traits|dmx\s+channels?|channel\s+dmx\s+function|\b[A-Z]{0,3}\s*\d{1,3}\s*[A-Z]{0,3}\s+channel\s+table\b)/i.test(text);
}

function tableHeadingCount(text) {
  return (text.match(/\b[A-Z]{0,3}\s*\d{1,3}\s*[A-Z]{0,3}\s+channel\s+table\b/gi) || []).length;
}

async function extractPdf(bytes) {
  const pdfDocument = await pdfjs.getDocument({ data: bytes, wasmUrl: './vendor/pdfjs/wasm/' }).promise;
  let worker = null;
  const pages = [];
  const thumbnails = [];
  for (let number = 1; number <= pdfDocument.numPages; number += 1) {
    announce('Reading the manual', number, pdfDocument.numPages);
    const page = await pdfDocument.getPage(number);
    const content = await page.getTextContent();
    let text = positionedText(content);
    const needsOcr = text.length < 80;
    const viewport = page.getViewport({ scale: needsOcr ? 1.8 : 0.55 });
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil(viewport.width);
    canvas.height = Math.ceil(viewport.height);
    await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
    thumbnails.push(await canvasToThumbnail(canvas));
    if (needsOcr) {
      worker ||= await ocrWorker();
      announce('Looking for DMX tables', number, pdfDocument.numPages);
      const result = await worker.recognize(canvas);
      text = result.data.text || '';
    }
    pages.push({ page: number, text });
  }
  if (worker) {
    const detailedPages = new Set();
    for (const page of pages) {
      const headings = tableHeadingCount(page.text);
      if (looksLikeDmxTable(page.text) && headings > 0 && headings <= 3) {
        detailedPages.add(page.page);
        if (page.page < pdfDocument.numPages) detailedPages.add(page.page + 1);
      }
      if (tableRangeCount(page.text) >= 5) detailedPages.add(page.page);
    }
    await worker.setParameters({
      tessedit_pageseg_mode: window.Tesseract.PSM.SINGLE_BLOCK,
      preserve_interword_spaces: '1',
    });
    for (const number of detailedPages) {
      announce('Reading the DMX table carefully', number, pdfDocument.numPages);
      const page = await pdfDocument.getPage(number);
      const viewport = page.getViewport({ scale: 3.2 });
      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(viewport.width);
      canvas.height = Math.ceil(viewport.height);
      await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
      const result = await worker.recognize(
        removeTableLines(canvas),
        {},
        { text: true, tsv: true },
      );
      const current = pages[number - 1];
      const detailed = positionedOcr(result.data.tsv) || result.data.text || '';
      if (tableTextScore(detailed) >= tableTextScore(current.text) * 0.7) {
        // Keep the broad, low-resolution pass as well. It is often better at
        // headings while the detailed pass is better at individual table rows.
        // Put the positioned pass first: on continuation pages a broad OCR
        // pass can announce the next table before it emits the rows above that
        // heading, which otherwise assigns those rows to the wrong mode.
        current.text = `${detailed}\n${current.text}`;
      }
    }
  }
  if (worker) await worker.terminate();
  return { pageCount: pdfDocument.numPages, pages, thumbnails };
}

async function extractImage(bytes, mime) {
  announce('Reading the photo', 1, 1);
  // Tesseract fetches URL inputs, and the site CSP (connect-src 'self')
  // rightly blocks blob: fetches — decode to a canvas ourselves instead,
  // matching every other recognize() call site. decodeImageBytes() also
  // covers HEIC photos (iPhone default format), which createImageBitmap
  // cannot decode natively.
  const { canvas, previewUrl } = await decodeImageBytes(bytes, mime);
  const worker = await ocrWorker();
  try {
    announce('Checking photo orientation', 1, 1);
    const detection = await detectRotation(worker, canvas);
    const oriented = rotateCanvas(canvas, detection.rotation);
    announce('Reading the photo', 1, 1);
    const result = await worker.recognize(oriented);
    const words = (result.data.words || []).filter(word => word.text && word.text.trim());
    const fullScore = words.reduce((sum, word) => sum + (word.confidence || 0), 0);
    // The orientation trial already OCR'd this same page (downscaled) to
    // pick a rotation; on a very high-resolution phone photo that
    // downscaled pass can score higher than this "real" full-size pass
    // (measured on the corpus this rotation-detection lane targets), so
    // keep whichever reading actually scored better instead of always
    // discarding the trial's text.
    const text = detection.score > fullScore ? detection.text : (result.data.text || '');
    // previewUrl is null for HEIC (and any other browser-undecodable source
    // we fell back on) since Chrome cannot render those bytes in an <img>
    // even unrotated — always build the thumbnail from the decoded canvas
    // in that case, same as the "photo needed rotating" path below.
    const thumbnail = (previewUrl && detection.rotation === 0) ? previewUrl : await canvasToThumbnail(oriented);
    return {
      pageCount: 1,
      pages: [{ page: 1, text, rotation: detection.rotation }],
      thumbnails: [thumbnail],
    };
  } finally {
    await worker.terminate();
    if (previewUrl) setTimeout(() => URL.revokeObjectURL(previewUrl), 30000);
  }
}

async function renderSourcePage(bytes, mime, pageNumber, rotation) {
  if (mime === 'application/pdf') {
    const pdfDocument = await pdfjs.getDocument({ data: bytes, wasmUrl: './vendor/pdfjs/wasm/' }).promise;
    const page = await pdfDocument.getPage(pageNumber);
    const viewport = page.getViewport({ scale: 3.2 });
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil(viewport.width);
    canvas.height = Math.ceil(viewport.height);
    await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
    return canvas;
  }
  // Region re-reads (extractRegion, below) go through the same decode path
  // as the initial extraction, including the HEIC fallback — no preview URL
  // is needed here, so skip creating one.
  const { canvas } = await decodeImageBytes(bytes, mime, { wantPreviewUrl: false });
  // extractImage() may have rotated this same photo to make it upright for
  // OCR (see detectRotation) — the region box the user draws is drawn over
  // that rotated thumbnail, so the crop source has to be rotated the same
  // way or the box lands on unrelated pixels.
  return rotateCanvas(canvas, rotation || 0);
}

async function extractRegion(bytes, mime, pageNumber, left, top, width, height, rotation) {
  announce('Reading the selected table', pageNumber, pageNumber);
  const source = await renderSourcePage(bytes, mime, pageNumber, rotation);
  const x = Math.max(0, Math.min(source.width - 1, Math.round(left * source.width)));
  const y = Math.max(0, Math.min(source.height - 1, Math.round(top * source.height)));
  const cropWidth = Math.max(20, Math.min(source.width - x, Math.round(width * source.width)));
  const cropHeight = Math.max(20, Math.min(source.height - y, Math.round(height * source.height)));
  const crop = document.createElement('canvas');
  crop.width = cropWidth;
  crop.height = cropHeight;
  crop.getContext('2d').drawImage(source, x, y, cropWidth, cropHeight, 0, 0, cropWidth, cropHeight);
  const worker = await ocrWorker();
  try {
    const normal = await worker.recognize(crop);
    const cleaned = await worker.recognize(removeTableLines(crop));
    return (cleaned.data.text || '').length > (normal.data.text || '').length
      ? cleaned.data.text || ''
      : normal.data.text || '';
  } finally {
    await worker.terminate();
  }
}

window.dmxtract = {
  extractManual: async (bytes, mime) => {
    const result = mime === 'application/pdf' ? await extractPdf(bytes) : await extractImage(bytes, mime);
    return JSON.stringify(result);
  },
  extractManualRegion: extractRegion,
};
