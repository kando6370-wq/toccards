type CacheEntry = {
  value: string;
  expiresAt: number | null;
  metadata: unknown;
};

export function createInMemoryKv(): KVNamespace {
  const entries = new Map<string, CacheEntry>();

  const readEntry = (key: string): CacheEntry | null => {
    const entry = entries.get(key);
    if (!entry) return null;
    if (entry.expiresAt !== null && entry.expiresAt <= Date.now()) {
      entries.delete(key);
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
      entries.set(key, {
        value: await cacheValueToString(value),
        expiresAt: expirationTime(options),
        metadata: options?.metadata ?? null,
      });
    },
    async delete(key: string) {
      entries.delete(key);
    },
    async getWithMetadata(key: string, typeOrOptions?: unknown) {
      const entry = readEntry(key);
      if (!entry) return { value: null, metadata: null, cacheStatus: null };
      const value = await (this as KVNamespace).get(key, typeOrOptions as never);
      return { value, metadata: entry.metadata, cacheStatus: null };
    },
    async list(options?: KVNamespaceListOptions) {
      const prefix = options?.prefix ?? "";
      const keys = [...entries.keys()]
        .filter((key) => readEntry(key) !== null && key.startsWith(prefix))
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
