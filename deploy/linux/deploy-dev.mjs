import { spawn, execFileSync } from "node:child_process";
import { createReadStream } from "node:fs";
import { cp, mkdir, mkdtemp, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repository = fileURLToPath(new URL("../../", import.meta.url));
const workers = path.join(repository, "apps/workers-api");
const quote = (value) => `'${value.replaceAll("'", `'"'"'`)}'`;

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: repository, stdio: "inherit", windowsHide: true });
    child.once("error", reject);
    child.once("close", (code) => code === 0 ? resolve() : reject(new Error(`${command} exited ${code}`)));
  });
}

async function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  if (args.some((arg) => arg !== "--dry-run")) throw new Error("Usage: deploy:dev [--dry-run]; set TOCCARDS_SSH_TARGET for SSH deployment");
  const target = process.env.TOCCARDS_SSH_TARGET;
  if (!dryRun && (!target || !/^[a-zA-Z0-9_][a-zA-Z0-9_.@-]*$/.test(target))) {
    throw new Error("Set TOCCARDS_SSH_TARGET to your configured SSH alias or user@192.168.50.201 before deployment");
  }
  const pnpm = process.env.npm_execpath;
  if (!pnpm) throw new Error("Run this command through pnpm --filter @kando/workers-api deploy:dev");
  await run(process.execPath, [pnpm, "--filter", "@kando/workers-api", "build:dev"]);

  const sha = execFileSync("git", ["rev-parse", "HEAD"], { cwd: repository, encoding: "utf8" }).trim();
  const dirty = execFileSync("git", ["status", "--porcelain"], { cwd: repository, encoding: "utf8" }).trim().length > 0;
  const ref = execFileSync("git", ["branch", "--show-current"], { cwd: repository, encoding: "utf8" }).trim() || "detached";
  const releaseId = `manual-${sha.slice(0, 12)}${dirty ? "-dirty" : ""}-${Date.now()}`;
  const stagingParent = path.join(workers, ".wrangler");
  await mkdir(stagingParent, { recursive: true });
  const artifact = await mkdtemp(path.join(stagingParent, "linux-release-"));
  // Explicit deployment inputs exclude .env files, credentials and local database/image volumes.
  const inputs = [
    ".dockerignore",
    "deploy/linux/docker-compose.yml", "deploy/linux/docker-compose.offline.yml",
    "deploy/linux/Caddyfile", "deploy/linux/Dockerfile", "deploy/linux/migrate.sh",
    "deploy/linux/preflight.mjs", "deploy/linux/ci/deploy-release.sh",
    "deploy/linux/offline/Dockerfile", "deploy/linux/offline/Postgres.Dockerfile",
    "deploy/linux/offline/postgres-entrypoint.sh", "deploy/linux/offline/prepare-node-runtime.sh",
    "deploy/linux/offline/web-server.mjs",
    "apps/workers-api/dist/linux", "apps/workers-api/src/db/postgres/migrations", "apps/admin-web/dist",
  ];
  for (const input of inputs) {
    const destination = path.join(artifact, input);
    await mkdir(path.dirname(destination), { recursive: true });
    await cp(path.join(repository, input), destination, { recursive: true });
  }
  await writeFile(path.join(artifact, "release-manifest.txt"), `sha=${sha}\nbranch=${ref}\nworking_tree_dirty=${dirty}\nbuilt_at=${new Date().toISOString()}\nsource=deploy-dev\n`);
  const archive = `${artifact}.tar.gz`;
  await run("tar", ["-czf", archive, "-C", artifact, "."]);
  console.log(`Linux dev release prepared: ${archive}`);
  if (dryRun) {
    console.log("Dry run completed. No SSH connection, migration or deployment was performed.");
    return;
  }
  const command = [
    "set -eu", "umask 077",
    'mkdir -p "$HOME/apps/toccards-test/incoming"',
    'release_incoming=$(mktemp -d "$HOME/apps/toccards-test/incoming/release.XXXXXXXX")',
    'tar -xzf - -C "$release_incoming"',
    `TOCCARDS_RELEASE_ID=${quote(releaseId)} bash "$release_incoming/deploy/linux/ci/deploy-release.sh" "$release_incoming"`,
  ].join("\n");
  await new Promise((resolve, reject) => {
    const ssh = spawn("ssh", ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", target, command], {
      stdio: ["pipe", "inherit", "inherit"], windowsHide: true,
    });
    const input = createReadStream(archive);
    input.once("error", (error) => { ssh.kill(); reject(error); });
    ssh.once("error", (error) => { input.destroy(); reject(error); });
    ssh.stdin.on("error", () => input.destroy());
    ssh.once("close", (code) => {
      input.destroy();
      code === 0 ? resolve() : reject(new Error(`Linux SSH deployment exited ${code}; local artifact retained at ${archive}`));
    });
    input.pipe(ssh.stdin);
  });
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
