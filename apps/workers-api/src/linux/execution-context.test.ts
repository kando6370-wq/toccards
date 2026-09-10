import { describe, expect, it } from "vitest";

import { BackgroundTaskRegistry } from "./execution-context";

describe("Linux execution context", () => {
  it("drains work registered through waitUntil before shutdown", async () => {
    const registry = new BackgroundTaskRegistry();
    const context = registry.createExecutionContext();
    let completed = false;

    context.waitUntil(Promise.resolve().then(() => {
      completed = true;
    }));
    await registry.drain();

    expect(completed).toBe(true);
  });
});
