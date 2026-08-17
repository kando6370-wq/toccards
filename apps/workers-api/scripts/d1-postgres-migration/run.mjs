import { createHash, randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const workerDirectory = join(scriptDirectory, "..", "..");
const wranglerEntrypoint = join(workerDirectory, "node_modules", "wrangler", "bin", "wrangler.js");
const configPath = join(workerDirectory, "wrangler.migration.toml");
const argumentsSet = new Set(process.argv.slice(2));

if (!argumentsSet.has("--confirm-dev")) {
  fail("必须显式传入 --confirm-dev；该工具只允许迁移 dev D1。", 2);
}
if (argumentsSet.has("--schema-only") && argumentsSet.has("--verify-only")) {
  fail("--schema-only 与 --verify-only 不能同时使用。", 2);
}

const mode = argumentsSet.has("--schema-only")
  ? "schema-only"
  : argumentsSet.has("--verify-only")
    ? "verify-only"
    : "migrate-and-verify";
if (mode === "migrate-and-verify" && !argumentsSet.has("--confirm-source-write-frozen")) {
  fail(
    "完整迁移前必须先冻结 dev D1 写入，并显式传入 --confirm-source-write-frozen。",
    2,
  );
}
const token = randomBytes(32).toString("hex");
const port = await availablePort();
const baseUrl = `http://127.0.0.1:${port}`;
const recentWorkerOutput = [];

const worker = spawn(
  process.execPath,
  [
    wranglerEntrypoint,
    "dev",
    "--remote",
    "--config",
    configPath,
    "--port",
    String(port),
    "--var",
    `MIGRATION_TOKEN:${token}`,
  ],
  {
    cwd: workerDirectory,
    env: { ...process.env, NO_COLOR: "1" },
    stdio: ["ignore", "pipe", "pipe"],
  },
);

worker.stdout.on("data", rememberWorkerOutput);
worker.stderr.on("data", rememberWorkerOutput);

let stopping = false;
const stopForSignal = async () => {
  if (stopping) return;
  stopping = true;
  await stopWorker(worker);
  process.exitCode = 130;
};
process.once("SIGINT", stopForSignal);
process.once("SIGTERM", stopForSignal);

try {
  await waitUntilReady();
  console.log(JSON.stringify({ phase: "worker-ready", mode, port }));

  const manifest = await requestJson("/manifest");
  assert(manifest.ok, "迁移 manifest 读取失败");
  await verifySourceInventory(manifest);
  const sourceSchemas = await verifySourceSchemas(manifest.migrationTables);

  if (mode !== "verify-only") {
    const schemaResult = await requestJson("/schema", { method: "POST", body: {} });
    assert(schemaResult.ok, "PostgreSQL schema 执行失败");
    console.log(JSON.stringify({ phase: "schema-applied", ...schemaResult }));
  }

  const inventory = await requestJson("/schema");
  verifyTargetInventory(inventory, manifest);
  verifyTargetBusinessColumns(inventory, manifest.migrationTables);
  console.log(JSON.stringify({
    phase: "schema-verified",
    database: inventory.database,
    tables: inventory.tables.length,
    indexes: inventory.indexes.length,
    constraints: inventory.constraints.length,
    triggers: inventory.triggers.length,
    migrations: inventory.migrations.map((migration) => migration.name),
  }));

  if (mode === "schema-only") {
    console.log(JSON.stringify({ ok: true, mode, migratedTables: 0, verifiedTables: 0 }));
    process.exitCode = 0;
  } else {
    if (mode === "migrate-and-verify") {
      for (const table of manifest.migrationTables) {
        await migrateTable(table, sourceSchemas.get(table.name));
      }
    }

    const verification = [];
    for (const table of manifest.migrationTables) {
      verification.push(await verifyTable(table, sourceSchemas.get(table.name)));
    }
    console.log(JSON.stringify({
      ok: true,
      mode,
      migratedTables: mode === "migrate-and-verify" ? manifest.migrationTables.length : 0,
      verifiedTables: verification.length,
      verification,
    }));
    process.exitCode = 0;
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  if (recentWorkerOutput.length > 0) {
    console.error("Wrangler recent output:\n" + recentWorkerOutput.join(""));
  }
  process.exitCode = 1;
} finally {
  stopping = true;
  process.removeListener("SIGINT", stopForSignal);
  process.removeListener("SIGTERM", stopForSignal);
  await stopWorker(worker);
}

async function verifySourceSchemas(tables) {
  const schemas = new Map();
  for (const table of tables) {
    const result = await requestJson("/source-schema", {
      method: "POST",
      body: { table: table.name },
    });
    assert(result.ok, `dev D1 表 ${table.name} schema 读取失败`);
    assert(
      JSON.stringify(result.actualColumns) === JSON.stringify(table.columns),
      `dev D1 表 ${table.name} 列与固定迁移清单不一致：actual=${result.actualColumns.join(",")}`,
    );
    assert(result.nullCursorCount === 0, `dev D1 表 ${table.name} 存在空迁移游标`);
    schemas.set(table.name, result);
  }
  console.log(JSON.stringify({
    phase: "source-schema-verified",
    tables: schemas.size,
    rows: Array.from(schemas.values()).reduce((sum, schema) => sum + schema.rowCount, 0),
  }));
  return schemas;
}

async function verifySourceInventory(manifest) {
  const result = await requestJson("/source-inventory");
  assert(result.ok, "dev D1 全表 inventory 读取失败");
  const actual = result.tables.filter((table) => !table.startsWith("sqlite_")).sort();
  const expected = [
    ...manifest.migrationTables.map((table) => table.name),
    ...manifest.excludedSourceTables,
  ].sort();
  const missing = expected.filter((table) => !actual.includes(table));
  const unexpected = actual.filter((table) => !expected.includes(table));
  assert(missing.length === 0, `dev D1 缺少已知表：${missing.join(",")}`);
  assert(unexpected.length === 0, `dev D1 存在未分类表：${unexpected.join(",")}`);
  console.log(JSON.stringify({
    phase: "source-inventory-verified",
    businessTables: manifest.migrationTables.length,
    excludedTables: manifest.excludedSourceTables.length,
  }));
}

function verifyTargetInventory(inventory, manifest) {
  assert(inventory.ok, "PostgreSQL schema inventory 读取失败");
  const actual = new Set(inventory.tables.map((table) => table.table_name));
  const expected = new Set(manifest.expectedTargetTables);
  const missing = [...expected].filter((table) => !actual.has(table));
  const unexpected = [...actual].filter((table) => !expected.has(table));
  const excluded = manifest.excludedSourceTables.filter((table) => actual.has(table));
  assert(missing.length === 0, `PostgreSQL 缺少表：${missing.join(",")}`);
  assert(unexpected.length === 0, `PostgreSQL 存在未纳入迁移的表：${unexpected.join(",")}`);
  assert(excluded.length === 0, `PostgreSQL 错误创建了排除表：${excluded.join(",")}`);
  assert(inventory.migrations.length === 2, "PostgreSQL migration 记录数量不是 2");
  assert(
    inventory.constraints.every((constraint) => constraint.validated),
    "PostgreSQL 存在未验证约束",
  );
  const triggerNames = new Set(inventory.triggers.map((trigger) => trigger.trigger_name));
  assert(
    triggerNames.has("trg_current_price_pointer_published")
      && triggerNames.has("trg_price_ingest_batch_protect_pointer"),
    "价格发布保护 trigger 不完整",
  );
}

function verifyTargetBusinessColumns(inventory, tables) {
  const byTable = new Map();
  for (const column of inventory.columns) {
    const names = byTable.get(column.table_name) ?? [];
    names.push(column.column_name);
    byTable.set(column.table_name, names);
  }

  for (const table of tables) {
    const expected = [...table.columns];
    if (table.name === "collection_item" || table.name === "collection_item_event") {
      expected.push("price_series_id");
    }
    assert(
      JSON.stringify(byTable.get(table.name)) === JSON.stringify(expected),
      `PostgreSQL 表 ${table.name} 列与迁移合同不一致`,
    );
  }
}

async function migrateTable(table, sourceSchema) {
  assert(sourceSchema, `缺少 ${table.name} 的源 schema 证据`);
  let cursor = null;
  let rowsRead = 0;
  let rowsWritten = 0;
  let batches = 0;
  let maxPayloadBytes = 0;

  while (true) {
    const result = await requestJson("/migrate-batch", {
      method: "POST",
      body: { table: table.name, cursor },
    });
    assert(result.ok, `表 ${table.name} 批次迁移失败`);
    if (result.done) break;
    assert(result.nextCursor !== cursor, `表 ${table.name} 迁移游标未推进`);
    cursor = result.nextCursor;
    rowsRead += result.rowsRead;
    rowsWritten += result.rowsWritten;
    batches += 1;
    maxPayloadBytes = Math.max(maxPayloadBytes, result.payloadBytes);
    if (batches % 25 === 0) {
      console.log(JSON.stringify({ phase: "migrate-progress", table: table.name, batches, rowsRead }));
    }
  }

  assert(rowsRead === sourceSchema.rowCount, `表 ${table.name} 读取行数与源计数不一致`);
  console.log(JSON.stringify({
    phase: "table-migrated",
    table: table.name,
    sourceRows: sourceSchema.rowCount,
    rowsWritten,
    batches,
    maxPayloadBytes,
  }));
}

async function verifyTable(table, sourceSchema) {
  assert(sourceSchema, `缺少 ${table.name} 的源 schema 证据`);
  let cursor = null;
  let rows = 0;
  let batches = 0;
  const aggregate = createHash("sha256");

  while (true) {
    const result = await requestJson("/verify-batch", {
      method: "POST",
      body: { table: table.name, cursor },
    });
    assert(result.ok, `表 ${table.name} 数据摘要不一致`);
    aggregate.update(result.sourceDigest);
    if (result.done) break;
    assert(result.nextCursor !== cursor, `表 ${table.name} 校验游标未推进`);
    assert(result.sourceRows === result.targetRows, `表 ${table.name} 批次行数不一致`);
    cursor = result.nextCursor;
    rows += result.sourceRows;
    batches += 1;
  }

  assert(rows === sourceSchema.rowCount, `表 ${table.name} 目标行数与源计数不一致`);
  const digest = aggregate.digest("hex");
  console.log(JSON.stringify({
    phase: "table-verified",
    table: table.name,
    rows,
    batches,
    digest,
  }));
  return { table: table.name, rows, digest };
}

async function requestJson(path, options = {}) {
  const requestOptions = {
    method: options.method ?? "GET",
    headers: {
      authorization: `Bearer ${token}`,
      ...(options.body === undefined ? {} : { "content-type": "application/json" }),
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  };
  let lastError;

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(`${baseUrl}${path}`, {
        ...requestOptions,
        signal: AbortSignal.timeout(55_000),
      });
      const payload = await response.json();
      if (!response.ok) {
        throw new Error(`${path} HTTP ${response.status}: ${payload.message ?? payload.code ?? "error"}`);
      }
      return payload;
    } catch (error) {
      lastError = error;
      if (attempt < 3) await delay(250 * attempt);
    }
  }
  throw lastError;
}

async function waitUntilReady() {
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    if (worker.exitCode !== null) {
      throw new Error(`Wrangler dev 提前退出，exit=${worker.exitCode}`);
    }
    try {
      const response = await fetch(`${baseUrl}/health`, {
        headers: { authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(2_000),
      });
      if (response.ok) return;
    } catch {
      // Wrangler remote preview is still starting.
    }
    await delay(500);
  }
  throw new Error("Wrangler remote preview 在 90 秒内未就绪");
}

function rememberWorkerOutput(chunk) {
  recentWorkerOutput.push(String(chunk));
  while (recentWorkerOutput.length > 40) recentWorkerOutput.shift();
}

async function stopWorker(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill("SIGTERM");
  const exited = await Promise.race([
    new Promise((resolve) => child.once("exit", () => resolve(true))),
    delay(5_000).then(() => false),
  ]);
  if (!exited && child.exitCode === null) child.kill("SIGKILL");
}

function availablePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : null;
      server.close((error) => {
        if (error) reject(error);
        else if (port === null) reject(new Error("无法分配本地端口"));
        else resolve(port);
      });
    });
  });
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function fail(message, exitCode) {
  console.error(message);
  process.exit(exitCode);
}
