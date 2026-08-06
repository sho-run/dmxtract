# Third-party notices

DMXtract source code is MIT licensed. The following bundled resources retain
their original licenses.

| Resource | Use | License |
| --- | --- | --- |
| Nunito | Interface typeface | SIL Open Font License 1.1 |
| Comfortaa | sho.run attribution wordmark | SIL Open Font License 1.1 |
| JetBrains Mono | Technical values | SIL Open Font License 1.1 |
| DSEG7 Classic | DMX and hardware readouts | SIL Open Font License 1.1 |
| Material Symbols/Icons | Outlined interface icons | Apache License 2.0 |
| PDF.js | Local PDF extraction | Apache License 2.0 |
| Tesseract.js / Tesseract | Local OCR | Apache License 2.0 |
| pyGDTF AttributeDefinitions.xml | GDTF 1.2 channel-type catalog | MIT |
| Open Lighting Architecture | Optional macOS DMX transport | LGPL-2.1-or-later; bundled source and build records required |

The sho.run name appears only as project attribution, copyright holder,
repository owner, and canonical host. No sho.run logo artwork, private product
source, copied design tokens, service credentials, or private fixture data are
bundled. DMXtract's icon and application palette were independently authored
for this repository.

Exact notices for the bundled fonts, PDF.js, Tesseract.js, and Tesseract core
are stored in `third_party/licenses/`. Before distributing a signed bridge,
add the exact OLA license/source bundle and record release checksums in its
build record.

## Netlify Functions dependencies

`netlify/functions/phone-link-signal.mjs` depends on `@netlify/blobs` for
session storage (see `package.json`). Its full transitive dependency tree, as
resolved in `package-lock.json`, is:

| Package | Version | License |
| --- | --- | --- |
| @envelop/instrumentation | 1.0.0 | MIT |
| @fastify/busboy | 3.2.0 | MIT |
| @netlify/blobs | 10.7.12 | MIT |
| @netlify/dev-utils | 4.4.7 | MIT |
| @netlify/otel | 6.0.5 | MIT |
| @netlify/runtime-utils | 2.3.0 | MIT |
| @opentelemetry/api | 1.9.1 | Apache-2.0 |
| @opentelemetry/api-logs | 0.220.0 | Apache-2.0 |
| @opentelemetry/context-async-hooks | 2.9.0 | Apache-2.0 |
| @opentelemetry/core | 2.8.0, 2.9.0 | Apache-2.0 |
| @opentelemetry/instrumentation | 0.220.0 | Apache-2.0 |
| @opentelemetry/resources | 2.9.0 | Apache-2.0 |
| @opentelemetry/sdk-trace | 2.9.0 | Apache-2.0 |
| @opentelemetry/sdk-trace-base | 2.9.0 | Apache-2.0 |
| @opentelemetry/sdk-trace-node | 2.9.0 | Apache-2.0 |
| @opentelemetry/semantic-conventions | 1.43.0 | Apache-2.0 |
| @whatwg-node/disposablestack | 0.0.6 | MIT |
| @whatwg-node/fetch | 0.10.13 | MIT |
| @whatwg-node/node-fetch | 0.8.6 | MIT |
| @whatwg-node/promise-helpers | 1.3.2 | MIT |
| @whatwg-node/server | 0.11.0 | MIT |
| ansis | 4.3.1 | ISC |
| atomically | 2.1.1 | MIT |
| callsite | 1.0.0 | MIT (see note below) |
| chokidar | 4.0.3 | MIT |
| cjs-module-lexer | 2.2.0 | MIT |
| debug | 4.4.3 | MIT |
| decache | 4.6.2 | MIT |
| dettle | 1.0.5 | MIT |
| dot-prop | 9.0.0 | MIT |
| empathic | 2.0.1 | MIT |
| env-paths | 3.0.0 | MIT |
| es-module-lexer | 2.3.1 | MIT |
| image-size | 2.0.2 | MIT |
| import-in-the-middle | 3.3.3 | Apache-2.0 |
| jpeg-js | 0.4.4 | BSD-3-Clause |
| js-image-generator | 1.0.4 | ISC |
| module-details-from-path | 1.0.4 | MIT |
| ms | 2.1.3 | MIT |
| parse-gitignore | 2.0.0 | MIT |
| readdirp | 4.1.2 | MIT |
| require-in-the-middle | 8.0.1 | MIT |
| semver | 7.8.5 | ISC |
| stubborn-fs | 2.0.0 | MIT |
| stubborn-utils | 1.0.2 | MIT |
| tmp | 0.2.7 | MIT |
| tmp-promise | 3.0.3 | MIT |
| tslib | 2.8.1 | 0BSD |
| type-fest | 4.41.0 | MIT OR CC0-1.0 |
| urlpattern-polyfill | 10.1.0 | MIT |
| when-exit | 2.1.5 | MIT |

`callsite@1.0.0` (a transitive dependency of `decache`, itself transitive
under `@netlify/blobs`) omits a `license` field in its `package.json`, which
makes the npm registry report it as "Proprietary" by default. Its bundled
`Readme.md` states `## License` / `MIT` in full, so the actual license is
MIT; this is a metadata gap in the upstream package, not an unlicensed
dependency, and needs no replacement or vendoring.

None of the above ships in the Flutter web build or the bridge binary — they
run only inside the Netlify Function's server-side execution environment.
