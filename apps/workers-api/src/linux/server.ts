import { serve } from "@hono/node-server";

import { app, runScheduledTasks } from "../app";
import { loadLinuxRuntime } from "./config";
import { BackgroundTaskRegistry } from "./execution-context";

const runtime = loadLinuxRuntime();
const backgroundTasks = new BackgroundTaskRegistry();
let scheduledTask: Promise<void> | null = null;
let shuttingDown = false;

const server = serve(
  {
    fetch: (request) =>
      app.fetch(request, runtime.env, backgroundTasks.createExecutionContext()),
    hostname: runtime.hostname,
    port: runtime.port,
  },
  ({ address, port }) => {
    console.log(`Linux test API listening on http://${address}:${port}`);
  },
);

const scheduledTimer = setInterval(() => {
  if (scheduledTask) return;
  scheduledTask = runScheduledTasks(runtime.env)
    .catch((error) => {
      console.error("Linux scheduled task failed.", error);
    })
    .finally(() => {
      scheduledTask = null;
    });
}, runtime.scheduledTaskIntervalMs);
scheduledTimer.unref();

process.once("SIGINT", () => handleSignal("SIGINT"));
process.once("SIGTERM", () => handleSignal("SIGTERM"));

function handleSignal(signal: string): void {
  void shutdown(signal).catch((error) => {
    console.error("Linux test API shutdown failed.", error);
    process.exitCode = 1;
  });
}

async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`Received ${signal}; shutting down Linux test API.`);
  clearInterval(scheduledTimer);
  await closeServer();
  await scheduledTask;
  await backgroundTasks.drain();
  await runtime.database.close();
}

async function closeServer(): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => {
      if (error) reject(error);
      else resolve();
    });
  });
}
