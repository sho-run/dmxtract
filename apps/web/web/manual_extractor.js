import * as pdfjs from './vendor/pdfjs/pdf.min.mjs';

pdfjs.GlobalWorkerOptions.workerSrc = './vendor/pdfjs/pdf.worker.min.mjs';

function announce(stage, page, pages) {
  window.dispatchEvent(new CustomEvent('dmxtract-progress', { detail: { stage, page, pages } }));
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
  const blob = new Blob([bytes], { type: mime });
  const url = URL.createObjectURL(blob);
  const worker = await ocrWorker();
  try {
    const result = await worker.recognize(url);
    return { pageCount: 1, pages: [{ page: 1, text: result.data.text || '' }], thumbnails: [url] };
  } finally {
    await worker.terminate();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
  }
}

async function renderSourcePage(bytes, mime, pageNumber) {
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
  const bitmap = await createImageBitmap(new Blob([bytes], { type: mime }));
  const canvas = document.createElement('canvas');
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  canvas.getContext('2d').drawImage(bitmap, 0, 0);
  bitmap.close();
  return canvas;
}

async function extractRegion(bytes, mime, pageNumber, left, top, width, height) {
  announce('Reading the selected table', pageNumber, pageNumber);
  const source = await renderSourcePage(bytes, mime, pageNumber);
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
