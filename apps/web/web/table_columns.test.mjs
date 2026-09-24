import assert from 'node:assert/strict';
import test from 'node:test';

import { joinPositionedItems, withModeColumns } from './table_columns.js';

// A PDF.js text item centered at `at`.
const item = (text, at, width = 12, height = 12) => ({ text, x: at - width / 2, width, height });
const row = (...items) => ({ items });
const join = items => items.map(entry => entry.text).join('   ');

// Positions from the Eliminator FLUX FX manual's DMX Traits table as PDF.js
// reports them: count labels centered at 59/104/148, values at 198.
const fluxHeader = row(item('24 Ch', 59, 20), item('34 Ch', 104, 20), item('64 Ch', 148, 20), item('VALUES', 198, 30));

test('fills blank personality cells from where each number sits', () => {
  const lines = withModeColumns([
    fluxHeader,
    row(item('11', 59), item('000-255', 198, 30), item('Amber All', 254, 40)),
    row(item('11', 104), item('11', 148), item('000-255', 198, 30), item('Amber Intensity 1', 275, 70)),
  ], join);
  assert.deepEqual(lines.slice(1), [
    '11   –   –   000-255   Amber All',
    '–   11   11   000-255   Amber Intensity 1',
  ]);
});

test('leaves full rows, value rows, labels and page numbers as they were', () => {
  const rows = [
    fluxHeader,
    row(item('1', 59), item('1', 104), item('1', 148), item('000-255', 198, 30), item('All Heads Tilt', 265, 60)),
    row(item('152-153', 198, 30), item('Stop', 240, 20)),
    row(item('Amber Strobe', 267, 50)),
    row(item('17', 306)),
  ];
  assert.deepEqual(withModeColumns(rows, join), rows.map(entry => join(entry.items)));
});

// Eliminator Furious Five RG: a "(cont'd from prev page)" note sits in the
// position columns, so that row keeps its text for the parser's own
// continuation handling.
test('leaves a continuation note in the position columns alone', () => {
  const header = row(item('11-CH MODE', 81, 50), item('24-CH MODE', 169, 50));
  const lines = withModeColumns([
    header,
    row(item('3', 81), item('000 - 007', 258, 40), item('Off', 317, 15)),
    row(item('5 (', 138), item('cont’d from', 175, 45)),
  ], join);
  assert.deepEqual(lines.slice(1), ['3   –   000 - 007   Off', '5 (   cont’d from']);
});

test('reads a count label split into a number and its unit', () => {
  const header = row(item('30', 57, 8), item('ch', 64, 8), item('36', 105, 8), item('ch', 112, 8));
  const lines = withModeColumns([header, row(item('7', 108), item('000 - 255', 221, 40))], join);
  assert.equal(lines[1], '–   7   000 - 255');
});

// Chauvet DJ Intimidator Beam 360X: the page number sits under the first
// column; Rotosphere HP: a "000" value sits within the columns' reach.
test('leaves page footers, named rows and zero-padded values alone', () => {
  const lines = withModeColumns([
    fluxHeader,
    row(item('10', 59), item('Intimidator Beam 360X User Manual Rev. 1', 300, 200)),
    row(item('4', 104), item('Red 2', 130, 20), item('000-255', 198, 30)),
    row(item('000', 148), item('No function', 240, 50)),
  ], join);
  assert.deepEqual(lines.slice(1), [
    '10   Intimidator Beam 360X User Manual Rev. 1',
    '4   Red 2   000-255',
    '000   No function',
  ]);
});

test('does nothing without a count header, or when a number misses every column', () => {
  const plain = [row(item('11', 59), item('000-255', 198, 30))];
  assert.deepEqual(withModeColumns(plain, join), ['11   000-255']);
  const lines = withModeColumns([fluxHeader, row(item('11', 82), item('000-255', 198, 30))], join);
  assert.equal(lines[1], '11   000-255');
});

// Measured on ADJ's 7PZ IP manual: the enlarged initial of a small-caps
// heading ends 0.70 pt before the rest of the word, while the real word space
// in the same heading is 5.29 pt.
test('joins the pieces of a small-caps word, and nothing else', () => {
  const at = (text, x, width) => ({ text, x, width, height: 14 });
  assert.equal(
    joinPositionedItems([at('4 C', 100, 14), at('HANNEL', 114.7, 50), at('- HSI', 170, 30)]),
    '4 CHANNEL - HSI',
  );
  assert.equal(joinPositionedItems([at('Z', 100, 9), at('OOM', 109.7, 30)]), 'ZOOM');
  // Touching, but a quote mark and a number keep their space as before.
  assert.equal(joinPositionedItems([at('“', 100, 5), at('dXX', 105, 20)]), '“ dXX');
  assert.equal(joinPositionedItems([at('000', 100, 20), at('255', 120.5, 20)]), '000 255');
  assert.equal(joinPositionedItems([at('Red', 100, 20), at('Green', 140, 30)]), 'Red   Green');
});

// ADJ COB Cannon LP200X tells two personalities of one size apart with a
// letter ("8Ch-A 8Ch-B"); Mirage Par H IP writes it after a space ("9Ch A").
test('reads lettered personalities of one size as separate columns', () => {
  const header = row(item('5Ch', 54, 14), item('8Ch-A', 88, 22), item('8Ch-B', 122, 22), item('9Ch', 156, 14), item('FUNCTION', 448, 40));
  const lines = withModeColumns([header, row(item('1', 54), item('1', 88), item('1', 156), item('0-255', 401, 22))], join);
  assert.equal(lines[1], '1   1   –   1   0-255');
  const spaced = row(item('5Ch', 58.9, 20.8), item('6Ch', 106.2, 20.8), item('9Ch A', 156.1, 31.4), item('9Ch B', 205.6, 31.8), item('VALUES', 363, 43.8));
  const filled = withModeColumns([spaced, row(item('1', 106.2), item('7', 156.1), item('0 - 255', 363, 34))], join);
  assert.equal(filled[1], '–   1   7   –   0 - 255');
});

// ADJ ElectraPix Bar 16 prints each count over its unit a row down, with the
// VALUES label on a row between; Vizi Pix Z19 tells its two 58-channel
// personalities apart only in the unit row.
test('reads counts printed over their units', () => {
  const counts = row(item('5', 50, 5.3), item('6', 78.1, 5.3), item('7', 106.2, 5.3), item('FUNCTION', 483.2, 51.7));
  const values = row(item('VALUES', 367.9, 39.8));
  const units = row(item('CH', 50, 13.7), item('CH', 78.1, 13.7), item('CH', 106.2, 13.7));
  const red = row(item('1', 78.1, 5.3), item('1', 106.2, 5.3), item('0-255', 367.9, 22), item('All Red', 409, 30));
  assert.equal(withModeColumns([counts, values, units, red], join)[3], '–   1   1   0-255   All Red');
  const vizi = withModeColumns([
    row(item('43', 113, 10), item('58', 144, 10), item('58', 174, 10), item('VALUES', 308, 40)),
    row(item('Ch', 113, 10), item('Ch-A', 144, 18), item('Ch-B', 174, 18)),
    row(item('5', 113), item('000 - 255', 308, 40)),
  ], join);
  assert.equal(vizi[2], '5   –   –   000 - 255');
  // Units that don't sit under the counts make no header.
  const shifted = row(item('CH', 60, 13.7), item('CH', 90, 13.7), item('CH', 120, 13.7));
  const plain = withModeColumns([counts, values, shifted, row(item('1', 78.1, 5.3), item('0-255', 367.9, 22))], join);
  assert.equal(plain[3], '1   0-255');
});

// ADJ Mirage Par H IP: a merged cell's numbers are centered on the first
// line of a description that wraps around its value ("23 - 99") a line
// down. That text starts right of every value printed so far; a name printed
// before its value, as other tables do, starts left of them.
test('fills a row whose text starts in the description column', () => {
  const header = row(item('5Ch', 58.9, 20.8), item('6Ch', 106.2, 20.8), item('9Ch A', 156.1, 31.4), item('VALUES', 363, 43.8));
  const presets = row(item('2', 58.9, 6.1), item('9', 156.1, 6.1), item('White Color Temperature Presets,', 475.4, 165.5));
  const lines = withModeColumns([
    header,
    row(item('0 - 22', 363, 28.1), item('Open', 406, 20)),
    presets,
    row(item('3', 58.9, 6.1), item('Shutter', 300, 30)),
  ], join);
  assert.deepEqual(lines.slice(2), ['2   –   9   White Color Temperature Presets,', '3   Shutter']);
  // Before any value has been printed there is nothing to measure against.
  assert.equal(withModeColumns([header, presets], join)[1], '2   9   White Color Temperature Presets,');
});

// ADJ Encore Burst 200 prints a "2ACH" column the count pattern can't read;
// filling against the other five columns would shift every number under it.
test('leaves a header with an unreadable count label alone', () => {
  const header = row(
    item('1CH', 53.8, 22.4), item('2CH', 86.6, 22.4), item('2ACH', 121.4, 30), item('3CH', 156.2, 22.4),
    item('4CH', 187.4, 22.4), item('6CH', 219.2, 22.4), item('VALUE', 267, 30),
  );
  const dimmer = row(item('1', 54), item('1', 87), item('1', 156), item('1', 187), item('000 - 255', 266.6, 47.1));
  assert.equal(withModeColumns([header, dimmer], join)[1], '1   1   1   1   000 - 255');
});
