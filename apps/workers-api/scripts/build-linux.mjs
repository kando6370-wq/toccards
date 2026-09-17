import { mkdir, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";
import { linuxBuildOptions } from "./linux-build-options.mjs";

const outDir = new URL("../dist/linux/", import.meta.url);
await rm(outDir, { force: true, recursive: true });
await mkdir(outDir, { recursive: true });

await build({
  ...linuxBuildOptions,
  entryPoints: [fileURLToPath(new URL("../src/linux/server.ts", import.meta.url))],
  outfile: fileURLToPath(new URL("server.mjs", outDir)),
  sourcemap: true,
  logLevel: "info",
});
