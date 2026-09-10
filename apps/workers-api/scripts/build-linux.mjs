import { mkdir, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

const outDir = new URL("../dist/linux/", import.meta.url);
await rm(outDir, { force: true, recursive: true });
await mkdir(outDir, { recursive: true });

await build({
  entryPoints: [fileURLToPath(new URL("../src/linux/server.ts", import.meta.url))],
  outfile: fileURLToPath(new URL("server.mjs", outDir)),
  bundle: true,
  platform: "node",
  target: "node22",
  format: "esm",
  sourcemap: true,
  logLevel: "info",
});
