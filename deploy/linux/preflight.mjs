import { execFileSync } from "node:child_process";
import { readdirSync, realpathSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export function validateDeploymentEnvironment(env) {
  for (const key of [
    "POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD", "DATABASE_URL",
    "JWT_SECRET", "OBJECT_STORAGE_PATH", "ALLOWED_ORIGINS", "VECTOR_RECOGNITION_BASE_URL",
  ]) {
    if (!env[key]?.trim()) throw new Error(`${key} is required before Linux deployment`);
  }
  if (env.APP_ENVIRONMENT !== "development") {
    throw new Error("Linux deployment requires APP_ENVIRONMENT=development");
  }
  let database;
  let recognition;
  try {
    database = new URL(env.DATABASE_URL);
    recognition = new URL(env.VECTOR_RECOGNITION_BASE_URL);
  } catch {
    throw new Error("DATABASE_URL and VECTOR_RECOGNITION_BASE_URL must be valid URLs");
  }
  if (
    !["postgres:", "postgresql:"].includes(database.protocol) ||
    database.hostname !== "db" || (database.port && database.port !== "5432") ||
    decodeURIComponent(database.pathname.slice(1)) !== env.POSTGRES_DB ||
    decodeURIComponent(database.username) !== env.POSTGRES_USER ||
    decodeURIComponent(database.password) !== env.POSTGRES_PASSWORD ||
    database.search || database.hash
  ) {
    throw new Error("DATABASE_URL must use the Compose db:5432 service and matching POSTGRES_DB/USER/PASSWORD");
  }
  if (env.OBJECT_STORAGE_PATH !== "/data/scan-images") {
    throw new Error("OBJECT_STORAGE_PATH must use the mounted /data/scan-images volume");
  }
  if (
    !["https:", "http:"].includes(recognition.protocol) ||
    recognition.username || recognition.password || recognition.pathname !== "/" ||
    recognition.search || recognition.hash
  ) {
    throw new Error("VECTOR_RECOGNITION_BASE_URL must be an HTTP(S) origin without credentials or paths");
  }
  return { database: env.POSTGRES_DB, recognitionOrigin: recognition.origin };
}

function docker(args, environment = {}) {
  return execFileSync("docker", args, {
    encoding: "utf8", timeout: 30_000, stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, ...environment },
  }).trim();
}

export async function runPreflight(artifactRoot, env = process.env, runDocker = docker) {
  const config = validateDeploymentEnvironment(env);
  const files = readdirSync(path.join(artifactRoot, "apps/workers-api/src/db/postgres/migrations"))
    .filter((name) => /^\d{4}_[a-z0-9_]+\.sql$/.test(name)).sort();
  if (!files.length) throw new Error("No PostgreSQL migrations in the release artifact");
  const container = "toccards-linux-test-db-1";
  const containers = runDocker(["ps", "-a", "--format", "{{.Names}}"]);
  let applied = [];
  if (containers.split("\n").includes(container)) {
    if (runDocker(["inspect", container, "--format", "{{.State.Running}}"]) !== "true") {
      throw new Error("Existing dev database is stopped; restore its availability before deployment");
    }
    const sql = `SELECT json_build_object(
      'database',current_database(), 'username',current_user,
      'version',current_setting('server_version_num'),
      'migrations',COALESCE((SELECT json_agg(filename ORDER BY filename) FROM schema_migrations),'[]'::json))`;
    const command = 'PGCONNECT_TIMEOUT=10 PGGSSENCMODE=disable PGSSLMODE=disable PGOPTIONS="-c default_transaction_read_only=on -c statement_timeout=10000" psql -X -w -h 127.0.0.1 -v ON_ERROR_STOP=1 -At -c "$1"';
    const current = JSON.parse(runDocker([
      "exec", "--env", "PGPASSWORD", "--env", "PGUSER", "--env", "PGDATABASE",
      container, "sh", "-c", command, "preflight", sql,
    ], { PGPASSWORD: env.POSTGRES_PASSWORD, PGUSER: env.POSTGRES_USER, PGDATABASE: env.POSTGRES_DB }));
    if (current.database !== env.POSTGRES_DB || current.username !== env.POSTGRES_USER) {
      throw new Error("Running database identity differs from the proposed environment");
    }
    if (Math.floor(Number(current.version) / 10000) !== 18) {
      throw new Error("Existing dev database must use PostgreSQL 18; automatic major upgrades are not supported");
    }
    applied = current.migrations;
    const unknown = applied.filter((name) => !files.includes(name));
    if (unknown.length) throw new Error(`Database is ahead of this release: ${unknown.join(", ")}`);
  }
  const response = await fetch(`${config.recognitionOrigin}/health`, {
    signal: AbortSignal.timeout(10_000), redirect: "error",
  });
  const health = await response.json();
  if (!response.ok || health.ok !== true || health.dimensions !== 512 || health.metric !== "cosine" || health.top_k !== 5) {
    throw new Error("CF recognition health does not match the 512-dimensional cosine contract");
  }
  const result = { database: config.database, postgresMajor: 18, recognition: "reachable", pendingMigrations: files.filter((name) => !applied.includes(name)) };
  console.log(JSON.stringify(result));
  return result;
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    await runPreflight(path.resolve(process.argv[2] || "../.."));
  } catch (error) {
    console.error(`Linux preflight failed: ${error.message}`);
    process.exitCode = 1;
  }
}
