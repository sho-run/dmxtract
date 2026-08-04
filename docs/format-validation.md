# Format validation record

On 2026-08-03, `golden/simple-rgbw.dmxtract.json` was exported through the Rust core and checked against Open Fixture Library commit `c3101ea4b216486dfe26f3966402391325b21cab` using OFL's own `tests/fixtures-valid.js`. The fixture passed schema validation and OFL model import.

The same project was exported as GDTF 1.2. It parsed with `pygdtf` 1.4.5 and was accepted by an independent application importer with one source found, one record imported, and no failures.

These goldens prove format plumbing and basic RGBW semantics. Complex movers, wheels, 16-bit controls, and matrices remain separate regression cases and must pass before declaring those fixture classes production-ready.
