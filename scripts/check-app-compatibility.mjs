import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const repository = fileURLToPath(new URL("../", import.meta.url));
const git = (...args) => execFileSync("git", args, { cwd: repository, encoding: "utf8" }).trim();

export function validateBaselines(value) {
  if (value?.schemaVersion !== 1 || value.evidence !== "git-source-contracts-only" || !Array.isArray(value.baselines) || value.baselines.length === 0) {
    throw new Error("Compatibility baselines must explicitly identify source-only evidence");
  }
  const seen = new Set();
  for (const baseline of value.baselines) {
    if (!/^1\.\d+\.\d+$/.test(baseline.version) || !/^\d+$/.test(baseline.build) || baseline.tag !== "v" + baseline.version || !/^[0-9a-f]{40}$/.test(baseline.commit) || seen.has(baseline.version)) {
      throw new Error("Every marketing version needs one immutable Git baseline");
    }
    seen.add(baseline.version);
  }
  return value.baselines;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: repository, stdio: "inherit", windowsHide: true, ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(command + " exited " + result.status);
}

function flutter(args, cwd) {
  if (process.platform === "win32") {
    // All arguments are local generated paths or fixed test flags, never request input.
    const executable = execFileSync("where.exe", ["flutter.bat"], { encoding: "utf8" }).trim().split(/\r?\n/)[0];
    const command = [executable, ...args].map((arg) => '"' + arg.replaceAll('"', '""') + '"').join(" ");
    run(process.env.ComSpec || "cmd.exe", ["/d", "/s", "/c", '"' + command + '"'], { cwd, windowsVerbatimArguments: true });
  } else {
    run("flutter", args, { cwd });
  }
}

async function main() {
  const pnpm = process.env.npm_execpath;
  if (!pnpm) throw new Error("Run through pnpm test:app-compatibility");
  const configPath = path.join(repository, ".dart_tool/package_config.json");
  const packageConfig = JSON.parse(readFileSync(configPath, "utf8"));
  const baselines = validateBaselines(JSON.parse(readFileSync(new URL("./app-compatibility-baselines.json", import.meta.url), "utf8")));
  for (const baseline of baselines) {
    if (git("rev-parse", baseline.tag + "^{commit}") !== baseline.commit) throw new Error("Pinned tag changed or is missing: " + baseline.tag);
    const pubspec = execFileSync("git", ["show", baseline.commit + ":apps/flutter-app/pubspec.yaml"], { cwd: repository, encoding: "utf8" });
    if (!pubspec.split(/\r?\n/).includes("version: " + baseline.version + "+" + baseline.build)) throw new Error("Source version/build mismatch: " + baseline.tag);
  }
  const artifactRoot = path.join(repository, ".dart_tool/app-compatibility");
  mkdirSync(artifactRoot, { recursive: true });
  const output = mkdtempSync(path.join(artifactRoot, "run-"));
  const responses = path.join(output, "server-responses.json");
  const report = { schemaVersion: 1, evidence: "git-source-contracts-only", serverCommit: git("rev-parse", "HEAD"), serverWorkingTreeDirty: git("status", "--porcelain").length > 0, startedAt: new Date().toISOString(), status: "running", results: [] };
  const save = () => writeFileSync(path.join(output, "report.json"), JSON.stringify(report, null, 2));
  console.log("Compatibility evidence: " + output);
  save();
  try {
    run(process.execPath, [pnpm, "--filter", "@kando/workers-api", "test", "src/compatibility/app-contract.test.ts", "--reporter=dot"], { env: { ...process.env, APP_COMPATIBILITY_OUTPUT: responses } });
    const payload = JSON.parse(readFileSync(responses, "utf8"));
    if (payload.schemaVersion !== 1 || payload.producer !== "current-hono-api" || !payload.cases || Object.keys(payload.cases).length === 0) throw new Error("Current API did not produce every required contract response");
    for (const baseline of baselines) {
      const snapshot = path.join(output, baseline.tag);
      mkdirSync(snapshot);
      const archive = path.join(output, baseline.tag + ".tar");
      const sourcePaths = ["apps/flutter-app/lib", "apps/flutter-app/pubspec.yaml", "dart-packages/subscription-core/lib", "dart-packages/subscription-core/pubspec.yaml", "pubspec.yaml", "pubspec.lock"];
      const names = git("ls-tree", "-r", "--name-only", baseline.commit, "--", ...sourcePaths).split(/\r?\n/);
      if (!names.length || names.some((name) => name.startsWith("/") || name.split("/").includes("..") || !sourcePaths.some((prefix) => name === prefix || name.startsWith(prefix + "/")))) throw new Error("Unsafe or empty source archive");
      execFileSync("git", ["archive", "--format=tar", "--output=" + archive, baseline.commit, ...sourcePaths], { cwd: repository, stdio: "pipe" });
      execFileSync("tar", ["-xf", archive, "-C", snapshot], { cwd: repository, stdio: "pipe", windowsHide: true });
      const config = structuredClone(packageConfig);
      const roots = { kando_app: path.join(snapshot, "apps/flutter-app"), subscription_core: path.join(snapshot, "dart-packages/subscription-core") };
      for (const name of Object.keys(roots)) if (!config.packages.some((entry) => entry.name === name)) throw new Error("Missing workspace package " + name);
      for (const entry of config.packages) {
        const url = roots[entry.name] ? pathToFileURL(roots[entry.name] + path.sep).href : new URL(entry.rootUri, pathToFileURL(configPath)).href;
        entry.rootUri = url.endsWith("/") ? url : url + "/";
      }
      mkdirSync(path.join(snapshot, ".dart_tool"));
      const frozenConfig = path.join(snapshot, ".dart_tool/package_config.json");
      writeFileSync(frozenConfig, JSON.stringify(config, null, 2));
      copyFileSync(path.join(repository, ".dart_tool/package_graph.json"), path.join(snapshot, ".dart_tool/package_graph.json"));
      // A package-only marker makes fallback to the current checkout a compile error.
      const marker = path.join(snapshot, "apps/flutter-app/lib/compatibility_baseline_marker.dart");
      writeFileSync(marker, "const compatibilityBaselineCommit = '" + baseline.commit + "';\n", { flag: "wx" });
      const entry = path.join(snapshot, "apps/flutter-app/compatibility_entry_test.dart");
      const contracts = pathToFileURL(path.join(repository, "apps/flutter-app/tool/compatibility/client_contract_test.dart")).href;
      writeFileSync(entry, "import 'package:kando_app/compatibility_baseline_marker.dart';\nimport '" + contracts + "';\nvoid main() => runClientContracts(compatibilityBaselineCommit);\n", { flag: "wx" });
      flutter(["test", "--no-pub", "--no-test-assets", "--packages=" + frozenConfig, "--dart-define=APP_ENV=test", "--dart-define=APP_COMPATIBILITY_RESPONSES=" + responses, "--dart-define=APP_COMPATIBILITY_VERSION=" + baseline.version, "--dart-define=APP_COMPATIBILITY_BUILD=" + baseline.build, "--dart-define=APP_COMPATIBILITY_COMMIT=" + baseline.commit, entry, "--reporter=expanded"], path.join(snapshot, "apps/flutter-app"));
      report.results.push({ ...baseline, status: "passed", sourceTree: git("rev-parse", baseline.commit + ":apps/flutter-app/lib"), dependencyEnvironment: "current resolved packages; not historical signed artifact" });
      save();
    }
    report.status = "passed";
  } catch (error) {
    report.status = "failed";
    report.error = error.message;
    throw error;
  } finally {
    report.finishedAt = new Date().toISOString();
    save();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
