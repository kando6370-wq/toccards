import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  createAdminRequestHeaders,
  REQUEST_ID_HEADER,
} from "../src/request-id.ts";

const requestIdSource = await readFile(
  new URL("../src/request-id.ts", import.meta.url),
  "utf8",
);
const appSource = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");

test("Admin uses a UUID request id helper for every data fetch", () => {
  assert.match(requestIdSource, /export const REQUEST_ID_HEADER = "X-Request-ID"/);
  assert.match(requestIdSource, /headers\.set\(REQUEST_ID_HEADER,/);
  assert.equal(
    [...appSource.matchAll(/createAdminRequestHeaders\(/g)].length,
    3,
    "JSON requests, file downloads and authenticated scan images must share request correlation",
  );
});

test("Admin uses getRandomValues when randomUUID is unavailable because dev runs on insecure LAN HTTP", () => {
  const cryptoDescriptor = Object.getOwnPropertyDescriptor(globalThis, "crypto");
  let randomValuesCalls = 0;
  Object.defineProperty(globalThis, "crypto", {
    configurable: true,
    value: {
      getRandomValues(target) {
        randomValuesCalls += 1;
        target.set([
          0x00, 0x11, 0x22, 0x33,
          0x44, 0x55, 0x66, 0x77,
          0x88, 0x99, 0xaa, 0xbb,
          0xcc, 0xdd, 0xee, 0xff,
        ]);
        return target;
      },
    },
  });

  try {
    const headers = createAdminRequestHeaders();

    assert.equal(headers.get(REQUEST_ID_HEADER), "00112233-4455-4677-8899-aabbccddeeff");
    assert.equal(randomValuesCalls, 1);
  } finally {
    if (cryptoDescriptor) {
      Object.defineProperty(globalThis, "crypto", cryptoDescriptor);
    } else {
      delete globalThis.crypto;
    }
  }
});
