import { mkdir, rm } from "node:fs/promises";

import { build } from "esbuild";

const outDir = new URL("../dist/linux/", import.meta.url);
await rm(outDir, { force: true, recursive: true });
await mkdir(outDir, { recursive: true });

await build({
  entryPoints: [new URL("../src/linux/server.ts", import.meta.url).pathname],
  outfile: new URL("server.mjs", outDir).pathname,
  bundle: true,
  platform: "node",
  target: "node22",
  format: "esm",
  sourcemap: true,
  logLevel: "info",
});
