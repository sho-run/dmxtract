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
      if (/(channel value table|dmx channel assignments(?: and values)?|dmx charts?|dmx traits|dmx channels?|channel\s+dmx\s+function)/i.test(page.text)) {
        for (let nearby = Math.max(1, page.page - 2); nearby <= Math.min(pdfDocument.numPages, page.page + 2); nearby += 1) detailedPages.add(nearby);
      }
    }
    for (const number of detailedPages) {
      announce('Reading the DMX table carefully', number, pdfDocument.numPages);
      const page = await pdfDocument.getPage(number);
      const viewport = page.getViewport({ scale: 3.2 });
      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(viewport.width);
      canvas.height = Math.ceil(viewport.height);
      await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
      const result = await worker.recognize(removeTableLines(canvas));
      const current = pages[number - 1];
      if ((result.data.text || '').length > current.text.length) current.text = result.data.text;
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
  extractManual: async (bytes, mime) => JSON.stringify(
    mime === 'application/pdf' ? await extractPdf(bytes) : await extractImage(bytes, mime),
  ),
  extractManualRegion: extractRegion,
};
