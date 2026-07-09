#!/usr/bin/env node
import { pbkdf2Sync, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { ulid } from "ulid";

const args = parseArgs(process.argv.slice(2));
const email = String(args.email ?? process.env.ADMIN_EMAIL ?? "").trim().toLowerCase();
const password = String(args.password ?? process.env.ADMIN_PASSWORD ?? "");
const id = String(args.id ?? process.env.ADMIN_ID ?? ulid());
const database = String(args.database ?? "kando-db");
const isLocal = Boolean(args.local);
const shouldExecute = Boolean(args.execute);

if (!email || !password) {
  console.error("Usage: pnpm admin:init -- --email admin@example.com --password <password> [--local] [--execute]");
  process.exit(1);
}

const createdAt = new Date().toISOString();
const passwordHash = hashPassword(password);
const sql = [
  "INSERT INTO admin_user (id, email, password_hash, role, status, created_at)",
  `VALUES ('${escapeSql(id)}', '${escapeSql(email)}', '${escapeSql(passwordHash)}', 'super_admin', 'active', '${escapeSql(createdAt)}')`,
  "ON CONFLICT(email) DO NOTHING;",
].join("\n");

if (!shouldExecute) {
  console.log(sql);
  process.exit(0);
}

const wranglerArgs = ["d1", "execute", database, "--command", sql];
if (isLocal) wranglerArgs.push("--local");
const result = spawnSync("wrangler", wranglerArgs, { stdio: "inherit", shell: process.platform === "win32" });
process.exit(result.status ?? 1);

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith("--")) continue;
    const key = value.slice(2);
    const next = values[index + 1];
    if (!next || next.startsWith("--")) {
      parsed[key] = true;
    } else {
      parsed[key] = next;
      index += 1;
    }
  }
  return parsed;
}

function hashPassword(value) {
  const salt = randomBytes(16);
  const hash = pbkdf2Sync(value, salt, 100_000, 32, "sha256");
  return ["pbkdf2-sha256", "v1", "100000", base64Url(salt), base64Url(hash)].join("$");
}

function base64Url(buffer) {
  return Buffer.from(buffer).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function escapeSql(value) {
  return value.replace(/'/g, "''");
}
