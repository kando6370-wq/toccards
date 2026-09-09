import { app, runScheduledTasks } from "./app";
import type { Env, RuntimeEnv } from "./env";
import { createPostgresDatabase, runWithDatabaseLifecycle } from "./db/postgres-database";

export type { Env } from "./env";

const honoFetch = app.fetch.bind(app);

async function fetch(
  request: Request,
  env: RuntimeEnv,
  ctx?: ExecutionContext,
): Promise<Response> {
  if (!env?.HYPERDRIVE) throw new Error("HYPERDRIVE binding is required");
  if (!ctx) throw new Error("ExecutionContext is required for PostgreSQL requests");
  const database = createPostgresDatabase(env.HYPERDRIVE.connectionString);
  const requestEnv = { ...env, DB: database } as Env;
  return runWithDatabaseLifecycle(database, ctx, (trackedContext) =>
    Promise.resolve(honoFetch(request, requestEnv, trackedContext)));
}

function scheduled(
  _controller: ScheduledController,
  env: RuntimeEnv,
  ctx: ExecutionContext,
): void {
  if (!env.HYPERDRIVE) throw new Error("HYPERDRIVE binding is required");
  const database = createPostgresDatabase(env.HYPERDRIVE.connectionString);
  const scheduledEnv = { ...env, DB: database } as Env;
  ctx.waitUntil((async () => {
    try {
      await runScheduledTasks(scheduledEnv);
    } finally {
      await database.close();
    }
  })());
}

export default {
  fetch,
  request: app.request.bind(app),
  scheduled,
};
