import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tracked = execFileSync('git', ['ls-files', '-z'], {
  cwd: repositoryRoot,
  encoding: 'utf8',
}).split('\0').filter(Boolean);

const forbiddenText = [
  ['closed fixture-format identifier', ['ss', 'l2'].join('')],
  ['private product codename', ['show', 'up'].join('')],
  ['closed fixture-library vendor', ['scan', 'library'].join('')],
];
const forbiddenPath = ['design', '_system/'].join('');
const retiredAssetHashes = new Set([
  '268326e0e23dbb86c007b9e9247d26d4a587602c32fa26c88eca5a000d56cfee',
  '2b358aa933555f94c7cc00333763225c4025b5da3dea4c75b4f9e3692f3b59dd',
  '95071745147c4fb4eaf0c12811c02e4f72d3f63fd1c81b243e2574e420faec56',
  '8fd72e06efae6c5633d96dc84bcb512c5a8560b21de59fe5f30f367650015340',
]);

const failures = [];
for (const relative of tracked) {
  if (relative.toLowerCase().startsWith(forbiddenPath)) {
    failures.push(`${relative}: retired private design reference path`);
  }
  const bytes = fs.readFileSync(path.join(repositoryRoot, relative));
  const text = bytes.toString('utf8').toLowerCase();
  for (const [label, term] of forbiddenText) {
    if (text.includes(term)) failures.push(`${relative}: ${label}`);
  }
  const hash = crypto.createHash('sha256').update(bytes).digest('hex');
  if (retiredAssetHashes.has(hash)) {
    failures.push(`${relative}: retired copied-brand asset hash`);
  }
}

if (failures.length > 0) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log(`Source boundary is clean across ${tracked.length} tracked files.`);
