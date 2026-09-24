// How positionedText() turns a page's rows of PDF.js text items into lines:
// joinPositionedItems() for one row, withModeColumns() for the position
// cells of ADJ/Eliminator-style "DMX Traits" tables.
//
// Split out from manual_extractor.js (which otherwise pulls in the pdfjs
// import and DOM/canvas calls) so it can be unit tested directly - see
// table_columns.test.mjs.
//
// These tables give each DMX personality its own position column under a
// header row of channel counts ("24 Ch 34 Ch 64 Ch", "31Ch 55Ch 57Ch 60Ch
// 237Ch", "11-CH MODE 24-CH MODE") and leave a cell blank - no dash - where
// a personality lacks the function. Joined into plain text, "11   000-255
// Amber All" (only in 24 Ch) and "11   11   000-255 Amber Intensity 1" (34
// Ch and 64 Ch) no longer say which columns they sat in, but the page
// geometry still does: each number under the header lines up with its
// column's count label. Every such row is rewritten with one cell per
// column, "–" for a blank one, the way other manuals print it:
// "11   –   –   000-255   Amber All".

// Flattens one row's items, left to right: a wide gap (a table column)
// becomes three spaces and anything else one - except that two items that
// touch, letter against letter, are one word the PDF split for typography.
// A small-caps heading sets its enlarged initial apart ("7 C" + "HANNEL" is
// "7 CHANNEL", "Z" + "OOM" is "ZOOM"), and a space there left every mode
// heading of ADJ's 7PZ IP manual unreadable. Touching is a gap under 15% of
// the text height; a real space is about twice that.
export function joinPositionedItems(items) {
  let text = '';
  let right = null;
  let previous = null;
  for (const item of items) {
    if (previous) {
      const gap = item.x - right;
      const touching = gap < item.height * 0.15
        && /\p{L}$/u.test(previous.text) && /^\p{L}/u.test(item.text);
      text += touching ? '' : gap > 18 ? '   ' : ' ';
    }
    text += item.text;
    right = Math.max(right ?? item.x, item.x + item.width);
    previous = item;
  }
  return text.trim();
}

// A count's unit, with the letter that tells two personalities of one size
// apart ("8Ch-A 8Ch-B" on COB Cannon LP200X, "9Ch A" on Par Z300 RGBA).
const UNIT = String.raw`ch(?:\s*-\s*[a-z]|\s+[a-z])?`;
const COUNT_LABEL = new RegExp(String.raw`^\d{1,3}\s*-?\s*${UNIT}(?:\s+mode)?$`, 'i');
const COUNT_UNIT = new RegExp(String.raw`^-?\s*${UNIT}(?:\s+mode)?$`, 'i');
const STACKED_UNIT = new RegExp(`^${UNIT}$`, 'i');
const HEADER_WORD = /^(?:dmx|(?:dmx\s+)?values?|function|description)$/i;
// A position is never zero-padded: "000" under the columns is a DMX value.
const POSITION = /^[1-9]\d{0,2}$/;
const CELL = /^(?:[1-9]\d{0,2}|[-–—])$/;
const VALUE_RANGE = /^\d{1,3}\s*[-–—]\s*\d{1,3}$/;

const center = item => item.x + item.width / 2;

// The centers, or null unless there are two or more personalities and no two
// share a label ("24 Ch" twice is a repeated row, not a header).
function distinctColumns(labels, centers) {
  const keys = labels.map(label => label.replace(/[\s-]+/g, '').toLowerCase());
  return centers.length >= 2 && new Set(keys).size === keys.length ? centers : null;
}

// The column centers of a channel-count header row, or null when the row
// isn't one.
function headerColumns(items) {
  const labels = [];
  const centers = [];
  for (let index = 0; index < items.length; index += 1) {
    const item = items[index];
    if (COUNT_LABEL.test(item.text)) {
      labels.push(item.text);
      centers.push(center(item));
      continue;
    }
    // "24" and "Ch" can arrive as two neighbouring text items.
    const unit = items[index + 1];
    if (/^\d{1,3}$/.test(item.text) && unit && COUNT_UNIT.test(unit.text)
      && unit.x - (item.x + item.width) < 6) {
      labels.push(item.text + unit.text);
      centers.push((item.x + unit.x + unit.width) / 2);
      index += 1;
      continue;
    }
    // A count label this can't read ("2ACH" on Encore Burst 200) leaves a
    // column out, and every number under it would be put in a neighbour.
    if (/^\d{1,3}\s*-?\s*[a-z]{1,3}\s*ch\b/i.test(item.text)) return null;
  }
  return distinctColumns(labels, centers);
}

// The same for counts printed over their units a row down ("58" above
// "Ch-A" on Vizi Pix Z19, "126" above "CH" on Jolt Panel FX2), with the
// VALUES label sometimes on a row between: rows[index] holds only counts and
// header words, and one of the next two rows only units, one under each count.
function stackedColumns(rows, index) {
  const items = rows[index].items;
  const counts = items.filter(item => POSITION.test(item.text));
  if (counts.length < 2 || !items.every(item => POSITION.test(item.text) || HEADER_WORD.test(item.text))) {
    return null;
  }
  const pitch = Math.min(...counts.slice(1).map((item, i) => center(item) - center(counts[i])));
  for (const row of rows.slice(index + 1, index + 3)) {
    if (row.items.every(item => HEADER_WORD.test(item.text))) continue;
    const units = row.items;
    if (units.length !== counts.length
      || !units.every((unit, i) => STACKED_UNIT.test(unit.text)
        && Math.abs(center(unit) - center(counts[i])) <= pitch * 0.25)) {
      return null;
    }
    return distinctColumns(counts.map((count, i) => count.text + units[i].text), counts.map(center));
  }
  return null;
}

// The pitch of a header's columns and the x span they cover.
function columnSpan(columns) {
  const pitch = Math.min(...columns.slice(1).map((value, index) => value - columns[index]));
  return { pitch, left: columns[0] - pitch / 2, right: columns[columns.length - 1] + pitch / 2 };
}

// The row rewritten with one cell per column, or null to leave it as it is:
// nothing sits under the columns, something there isn't a bare number or
// dash (a "(cont'd from prev page)" note, say), a number doesn't line up
// with any column, no cell is blank, or the row goes on with anything but a
// DMX value or the description column. That last keeps this to the DMX
// Traits layout, where a row's cells are followed by its value, by nothing,
// or by a line of text that starts right of every value printed so far
// (`valueRight`): a merged cell's numbers centered on a description that
// wraps around its value ("White Color Temperature Presets," above "23 -
// 99"), or on the second half of a name ("Outer Strobe Dura-" / "tion").
// Other tables name the function before the value, and a page footer ("10
// Intimidator Beam 360X User Manual") can sit under a column too.
function explicitRow(items, columns, joinRow, valueRight) {
  const { pitch, left, right } = columnSpan(columns);
  const tolerance = pitch * 0.4;
  const under = items.filter(item => center(item) >= left && center(item) <= right);
  if (!under.some(item => POSITION.test(item.text))) return null;
  if (!under.every(item => CELL.test(item.text))) return null;
  const after = items.filter(item => !under.includes(item));
  if (after.length && !/^\d/.test(after[0].text)
    && !(valueRight !== null && after[0].x > valueRight)) {
    return null;
  }
  const cells = columns.map(() => null);
  for (const item of under) {
    let nearest = 0;
    for (let column = 1; column < columns.length; column += 1) {
      if (Math.abs(center(item) - columns[column]) < Math.abs(center(item) - columns[nearest])) {
        nearest = column;
      }
    }
    if (Math.abs(center(item) - columns[nearest]) > tolerance || cells[nearest] !== null) return null;
    cells[nearest] = /^\d/.test(item.text) ? item.text : '–';
  }
  if (cells.every(cell => cell !== null)) return null;
  return [...cells.map(cell => cell ?? '–'), joinRow(after)].filter(Boolean).join('   ');
}

// `rows` are a page's positionedText() rows, top to bottom, each with its
// items sorted left to right; `joinRow` flattens a list of items the way
// positionedText() always has. Returns one text line per row.
export function withModeColumns(rows, joinRow) {
  let columns = null;
  let valueRight = null;
  return rows.map((row, index) => {
    const header = headerColumns(row.items) ?? stackedColumns(rows, index);
    if (header) {
      columns = header;
      valueRight = null;
      return joinRow(row.items);
    }
    if (!columns) return joinRow(row.items);
    const line = explicitRow(row.items, columns, joinRow, valueRight) ?? joinRow(row.items);
    // The VALUES column's right edge, from the value ranges printed in it.
    const value = row.items.find(item => center(item) > columnSpan(columns).right);
    if (value && VALUE_RANGE.test(value.text)) {
      valueRight = Math.max(valueRight ?? 0, value.x + value.width);
    }
    return line;
  });
}
