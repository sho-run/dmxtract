import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const publishRoot = resolve(process.argv[2] ?? join(repositoryRoot, "apps/web/build/web"));
const failures = [];

const requiredFiles = [
  "index.html",
  "about/index.html",
  "privacy/index.html",
  "llms.txt",
  "robots.txt",
  "sitemap.xml",
  "_headers",
  "_redirects",
  "flutter_bootstrap.js",
  "main.dart.js",
  "canvaskit/canvaskit.js",
  "canvaskit/canvaskit.wasm",
  "canvaskit/chromium/canvaskit.js",
  "canvaskit/chromium/canvaskit.wasm",
  "assets/FontManifest.json",
  "wasm/dmxtract_core.js",
  "wasm/dmxtract_core_bg.wasm",
  "vendor/pdfjs/pdf.worker.min.mjs",
  "vendor/tesseract/worker.min.js",
  "schemas/fixture-v1.json",
];

for (const relative of requiredFiles) {
  const absolute = join(publishRoot, relative);
  if (!existsSync(absolute) || !statSync(absolute).isFile() || statSync(absolute).size === 0) {
    failures.push(`${relative}: required release file is missing or empty`);
  }
}

const bootstrapPath = join(publishRoot, "flutter_bootstrap.js");
if (existsSync(bootstrapPath)) {
  const bootstrap = readFileSync(bootstrapPath, "utf8");
  if (!/canvasKitBaseUrl\s*:\s*["']\/canvaskit\//.test(bootstrap)) {
    failures.push("flutter_bootstrap.js: CanvasKit is not pinned to the same origin");
  }
  if (!/fontFallbackBaseUrl\s*:\s*["']\/fonts\//.test(bootstrap)) {
    failures.push("flutter_bootstrap.js: font fallback is not pinned to the same origin");
  }
}

const headersPath = join(publishRoot, "_headers");
if (existsSync(headersPath)) {
  const headers = readFileSync(headersPath, "utf8");
  if (!headers.includes("Content-Security-Policy: default-src 'self'")) {
    failures.push("_headers: same-origin content security policy is missing");
  }
  if (!headers.includes("connect-src 'self' http://127.0.0.1:46321 ws://127.0.0.1:46321")) {
    failures.push("_headers: local bridge connections are not allowed");
  }
}

const redirectsPath = join(publishRoot, "_redirects");
if (existsSync(redirectsPath)) {
  const redirects = readFileSync(redirectsPath, "utf8");
  if (!/^\/\*\s+\/index\.html\s+200\s*$/m.test(redirects)) {
    failures.push("_redirects: SPA fallback is missing");
  }
}

const fontManifestPath = join(publishRoot, "assets/FontManifest.json");
if (existsSync(fontManifestPath)) {
  const fontManifest = JSON.parse(readFileSync(fontManifestPath, "utf8"));
  const roboto = fontManifest.find((entry) => entry.family === "Roboto");
  if (!roboto?.fonts?.every((font) => font.asset.startsWith("assets/fonts/Nunito-"))) {
    failures.push("assets/FontManifest.json: local Roboto startup alias is missing");
  }
}

const functionsRoot = join(repositoryRoot, "netlify/functions");
const functionFiles = readdirSync(functionsRoot, { withFileTypes: true })
  .filter((entry) => entry.isFile())
  .map((entry) => entry.name)
  .sort();
for (const filename of functionFiles) {
  const functionName = filename.replace(/\.[^.]+$/, "");
  if (!/^[A-Za-z0-9_-]+$/.test(functionName)) {
    failures.push(`netlify/functions/${filename}: invalid Netlify function name`);
  }
  if (/\.test\.|\.spec\./.test(filename)) {
    failures.push(`netlify/functions/${filename}: tests must not be deployed as functions`);
  }
}
if (functionFiles.join(",") !== "fixture-matches.mjs") {
  failures.push(`netlify/functions: unexpected deploy entries (${functionFiles.join(", ")})`);
}

if (failures.length > 0) {
  console.error(`Netlify release check failed:\n${failures.map((item) => `- ${item}`).join("\n")}`);
  process.exit(1);
}

console.log(`Netlify release is self-contained and structurally valid in ${publishRoot}`);
