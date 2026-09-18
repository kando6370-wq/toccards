export const linuxBuildOptions = {
  bundle: true,
  platform: "node",
  target: "node22",
  format: "esm",
  // Bundled CommonJS dependencies (including Apple's SDK) still require Node builtins.
  banner: { js: 'import { createRequire as __linuxCreateRequire } from "node:module"; const require = __linuxCreateRequire(import.meta.url);' },
};
