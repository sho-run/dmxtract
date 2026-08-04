# Format validation record

On 2026-08-03, `golden/simple-rgbw.dmxtract.json` was exported through the Rust core and checked against Open Fixture Library commit `c3101ea4b216486dfe26f3966402391325b21cab` using OFL's own `tests/fixtures-valid.js`. The fixture passed schema validation and OFL model import.

The same project was exported as GDTF 1.2. It parsed with `pygdtf` 1.4.5 and was accepted by an independent application importer with one source found, one record imported, and no failures.

These goldens prove format plumbing and basic RGBW semantics.

On 2026-08-04, the browser exporter was also exercised with three complex real manuals: the Betopper LM3715R, Chauvet Professional COLORado PXL Curve 12, and Martin MAC Aura Raven XIP. All three generated OFL fixtures passed OFL's `tests/fixtures-valid.js` at the pinned commit above. Their GDTF archives parsed with `pygdtf` 1.4.5, including every extracted personality, 16-bit coarse/fine channel pairing, wheel data, and the Raven's 851-channel Plaid personality split across DMX breaks 1 and 2.

The real manuals remain local test inputs and are not distributed with the repository. Synthetic regressions preserve the relevant behavior without copying manual content.
