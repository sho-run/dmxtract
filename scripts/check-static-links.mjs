import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const publishRoot = resolve(process.argv[2] ?? join(repositoryRoot, "apps/web/build/web"));
const pages = ["index.html", "privacy/index.html"];
const failures = [];

for (const page of pages) {
  const absolutePage = join(publishRoot, page);
  if (!existsSync(absolutePage)) {
    failures.push(`${page}: page is missing`);
    continue;
  }
  const html = readFileSync(absolutePage, "utf8");
  for (const match of html.matchAll(/\b(?:href|src)=["']([^"']+)["']/g)) {
    const target = match[1];
    if (
      target.startsWith("http://") ||
      target.startsWith("https://") ||
      target.startsWith("data:") ||
      target.startsWith("#") ||
      target.includes("$FLUTTER_BASE_HREF")
    ) {
      continue;
    }
    const cleanTarget = target.split(/[?#]/, 1)[0];
    let localPath = cleanTarget.startsWith("/")
      ? join(publishRoot, cleanTarget)
      : join(dirname(absolutePage), cleanTarget);
    localPath = normalize(localPath);
    if (localPath.endsWith("/") || (existsSync(localPath) && statSync(localPath).isDirectory())) {
      localPath = join(localPath, "index.html");
    }
    if (!localPath.startsWith(publishRoot) || !existsSync(localPath)) {
      failures.push(`${page}: ${target}`);
    }
  }
}

if (failures.length > 0) {
  console.error(`Broken local links:\n${failures.map((item) => `- ${item}`).join("\n")}`);
  process.exit(1);
}

console.log(`Static links are valid in ${publishRoot}`);
