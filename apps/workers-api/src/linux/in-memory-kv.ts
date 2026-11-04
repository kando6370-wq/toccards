type CacheEntry = {
  value: string;
  expiresAt: number | null;
  metadata: unknown;
  sizeBytes: number;
};

const CLEANUP_INTERVAL_MS = 60_000;
const MAX_EXPIRING_ENTRIES = 10_000;
const MAX_EXPIRING_BYTES = 32 * 1024 * 1024;

export function createInMemoryKv(): KVNamespace {
  const entries = new Map<string, CacheEntry>();
  let expiringEntries = 0;
  let expiringBytes = 0;
  let cleanupTimer: ReturnType<typeof setTimeout> | null = null;

  const removeEntry = (key: string): void => {
    const entry = entries.get(key);
    if (!entry) return;
    entries.delete(key);
    if (entry.expiresAt !== null) {
      expiringEntries -= 1;
      expiringBytes -= entry.sizeBytes;
    }
  };

  const pruneExpired = (): void => {
    const now = Date.now();
    for (const [key, entry] of entries) {
      if (entry.expiresAt !== null && entry.expiresAt <= now) removeEntry(key);
    }
  };

  const syncCleanupTimer = (): void => {
    if (expiringEntries === 0) {
      if (cleanupTimer !== null) clearTimeout(cleanupTimer);
      cleanupTimer = null;
    } else if (cleanupTimer === null) {
      cleanupTimer = setTimeout(() => {
        cleanupTimer = null;
        pruneExpired();
        syncCleanupTimer();
      }, CLEANUP_INTERVAL_MS);
      cleanupTimer.unref();
    }
  };

  const readEntry = (key: string): CacheEntry | null => {
    const entry = entries.get(key);
    if (!entry) return null;
    if (entry.expiresAt !== null && entry.expiresAt <= Date.now()) {
      removeEntry(key);
      syncCleanupTimer();
      return null;
    }
    return entry;
  };

  return {
    async get(key: string, typeOrOptions?: unknown) {
      const entry = readEntry(key);
      if (!entry) return null;
      const type = typeof typeOrOptions === "string"
        ? typeOrOptions
        : (typeOrOptions as { type?: string } | undefined)?.type;
      if (type === "json") return JSON.parse(entry.value);
      if (type === "arrayBuffer") return new TextEncoder().encode(entry.value).buffer;
      if (type === "stream") {
        return new Blob([entry.value]).stream();
      }
      return entry.value;
    },
    async put(key: string, value: string | ArrayBuffer | ArrayBufferView | ReadableStream, options?: KVNamespacePutOptions) {
      const cachedValue = await cacheValueToString(value);
      const expiresAt = expirationTime(options);
      const sizeBytes = expiresAt === null ? 0 : (key.length + cachedValue.length) * 2;
      removeEntry(key);
      if (expiresAt !== null && (expiresAt <= Date.now() || sizeBytes > MAX_EXPIRING_BYTES)) {
        syncCleanupTimer();
        return;
      }
      entries.set(key, {
        value: cachedValue,
        expiresAt,
        metadata: options?.metadata ?? null,
        sizeBytes,
      });
      if (expiresAt !== null) {
        expiringEntries += 1;
        expiringBytes += sizeBytes;
        if (expiringEntries > MAX_EXPIRING_ENTRIES || expiringBytes > MAX_EXPIRING_BYTES) {
          pruneExpired();
        }
        while (expiringEntries > MAX_EXPIRING_ENTRIES || expiringBytes > MAX_EXPIRING_BYTES) {
          let oldestExpiringKey: string | null = null;
          for (const [candidateKey, entry] of entries) {
            if (entry.expiresAt !== null) {
              oldestExpiringKey = candidateKey;
              break;
            }
          }
          if (oldestExpiringKey === null) throw new Error("Expiring KV cache accounting is inconsistent");
          removeEntry(oldestExpiringKey);
        }
      }
      syncCleanupTimer();
    },
    async delete(key: string) {
      removeEntry(key);
      syncCleanupTimer();
    },
    async getWithMetadata(key: string, typeOrOptions?: unknown) {
      const entry = readEntry(key);
      if (!entry) return { value: null, metadata: null, cacheStatus: null };
      const value = await (this as KVNamespace).get(key, typeOrOptions as never);
      return { value, metadata: entry.metadata, cacheStatus: null };
    },
    async list(options?: KVNamespaceListOptions) {
      const prefix = options?.prefix ?? "";
      pruneExpired();
      syncCleanupTimer();
      const keys = [...entries.keys()]
        .filter((key) => key.startsWith(prefix))
        .sort()
        .slice(0, options?.limit ?? 1000)
        .map((name) => ({ name }));
      return { keys, list_complete: true, cacheStatus: null };
    },
  } as unknown as KVNamespace;
}

async function cacheValueToString(
  value: string | ArrayBuffer | ArrayBufferView | ReadableStream,
): Promise<string> {
  if (typeof value === "string") return value;
  if (value instanceof ReadableStream) {
    return new TextDecoder().decode(await new Response(value).arrayBuffer());
  }
  if (value instanceof ArrayBuffer) return new TextDecoder().decode(value);
  return new TextDecoder().decode(
    new Uint8Array(value.buffer, value.byteOffset, value.byteLength),
  );
}

function expirationTime(options: KVNamespacePutOptions | undefined): number | null {
  if (typeof options?.expiration === "number") return options.expiration * 1000;
  if (typeof options?.expirationTtl === "number") {
    return Date.now() + options.expirationTtl * 1000;
  }
  return null;
}
