import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { createFilesystemR2Bucket } from "./filesystem-r2";

const roots: string[] = [];

describe("Linux filesystem object storage", () => {
  afterEach(async () => {
    await Promise.all(roots.splice(0).map((root) => rm(root, { force: true, recursive: true })));
  });

  it("stores, reads and deletes scan images with content metadata", async () => {
    const root = await mkdtemp(join(tmpdir(), "toccards-r2-"));
    roots.push(root);
    const bucket = createFilesystemR2Bucket(root);

    await bucket.put("scans/user/scan.jpg", new Uint8Array([1, 2, 3]), {
      httpMetadata: { contentType: "image/jpeg" },
      customMetadata: { scanId: "scan" },
    });

    const object = await bucket.get("scans/user/scan.jpg");
    expect(object?.httpMetadata?.contentType).toBe("image/jpeg");
    expect(object?.customMetadata).toEqual({ scanId: "scan" });
    expect([...await object!.bytes()]).toEqual([1, 2, 3]);

    await bucket.delete("scans/user/scan.jpg");
    expect(await bucket.get("scans/user/scan.jpg")).toBeNull();
  });

  it("rejects object keys that escape the configured directory", async () => {
    const root = await mkdtemp(join(tmpdir(), "toccards-r2-"));
    roots.push(root);
    const bucket = createFilesystemR2Bucket(root);

    await expect(bucket.put("../escape.jpg", "bad")).rejects.toThrow(
      "Object key escapes the configured storage directory",
    );
  });
});
