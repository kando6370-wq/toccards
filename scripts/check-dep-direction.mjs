// 依赖方向校验（M0-8）：apps/ → packages/ 单向；packages/ 不得反向依赖 apps/。
// 参见 docs/tcg-card/02-architecture/monorepo.md §4。
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

function readPackages(subdir) {
  const base = join(root, subdir);
  if (!existsSync(base)) return [];
  return readdirSync(base, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => join(base, d.name, "package.json"))
    .filter((p) => existsSync(p))
    .map((p) => JSON.parse(readFileSync(p, "utf8")));
}

const appNames = new Set(readPackages("apps").map((p) => p.name));
const libs = readPackages("packages");

const violations = [];
for (const lib of libs) {
  const deps = {
    ...lib.dependencies,
    ...lib.devDependencies,
    ...lib.peerDependencies,
  };
  for (const dep of Object.keys(deps)) {
    if (appNames.has(dep)) {
      violations.push(`${lib.name} → ${dep}（packages 不可依赖 apps）`);
    }
  }
}

if (violations.length > 0) {
  console.error("依赖方向校验失败（apps → packages 单向）：");
  for (const v of violations) console.error(`  - ${v}`);
  process.exit(1);
}

console.log(`依赖方向校验通过：${libs.length} 个 package 均未反向依赖 apps。`);
