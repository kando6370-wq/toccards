import { createHash } from "node:crypto";
import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { dirname, resolve, sep } from "node:path";

type StoredMetadata = {
  contentType?: string;
  customMetadata?: Record<string, string>;
  uploaded: string;
};

export function createFilesystemR2Bucket(rootPath: string): R2Bucket {
  const root = resolve(rootPath);

  return {
    async put(
      key: string,
      value: ReadableStream | ArrayBuffer | ArrayBufferView | string | null | Blob,
      options?: R2PutOptions,
    ) {
      const filePath = objectPath(root, key);
      const bytes = await bodyBytes(value);
      const uploaded = new Date();
      const metadata: StoredMetadata = {
        contentType: contentType(options?.httpMetadata),
        customMetadata: options?.customMetadata,
        uploaded: uploaded.toISOString(),
      };
      await mkdir(dirname(filePath), { recursive: true });
      await Promise.all([
        writeFile(filePath, bytes),
        writeFile(metadataPath(filePath), JSON.stringify(metadata)),
      ]);
      return r2Object(key, bytes, metadata, uploaded);
    },
    async get(key: string) {
      const filePath = objectPath(root, key);
      try {
        const [bytes, metadata] = await Promise.all([
          readFile(filePath),
          readMetadata(filePath),
        ]);
        return r2ObjectBody(key, bytes, metadata);
      } catch (error) {
        if (isMissingFile(error)) return null;
        throw error;
      }
    },
    async delete(keys: string | string[]) {
      for (const key of Array.isArray(keys) ? keys : [keys]) {
        const filePath = objectPath(root, key);
        await Promise.all([
          rm(filePath, { force: true }),
          rm(metadataPath(filePath), { force: true }),
        ]);
      }
    },
    async head(key: string) {
      const filePath = objectPath(root, key);
      try {
        const [fileStat, metadata] = await Promise.all([
          stat(filePath),
          readMetadata(filePath),
        ]);
        return r2ObjectFromSize(key, fileStat.size, metadata);
      } catch (error) {
        if (isMissingFile(error)) return null;
        throw error;
      }
    },
  } as unknown as R2Bucket;
}

function objectPath(root: string, key: string): string {
  const filePath = resolve(root, key);
  if (filePath !== root && !filePath.startsWith(`${root}${sep}`)) {
    throw new Error("Object key escapes the configured storage directory");
  }
  return filePath;
}

function metadataPath(filePath: string): string {
  return `${filePath}.metadata.json`;
}

async function readMetadata(filePath: string): Promise<StoredMetadata> {
  try {
    return JSON.parse(await readFile(metadataPath(filePath), "utf8")) as StoredMetadata;
  } catch (error) {
    if (!isMissingFile(error)) throw error;
    const fileStat = await stat(filePath);
    return { uploaded: fileStat.mtime.toISOString() };
  }
}

async function bodyBytes(
  value: ReadableStream | ArrayBuffer | ArrayBufferView | string | null | Blob,
): Promise<Uint8Array> {
  if (value === null) return new Uint8Array();
  if (typeof value === "string") return new TextEncoder().encode(value);
  if (value instanceof Blob || value instanceof ReadableStream) {
    return new Uint8Array(await new Response(value).arrayBuffer());
  }
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
}

function contentType(metadata: R2HTTPMetadata | Headers | undefined): string | undefined {
  if (!metadata) return undefined;
  if (metadata instanceof Headers) return metadata.get("content-type") ?? undefined;
  return metadata.contentType;
}

function r2Object(
  key: string,
  bytes: Uint8Array,
  metadata: StoredMetadata,
  uploaded = new Date(metadata.uploaded),
): R2Object {
  return r2ObjectFromSize(key, bytes.byteLength, metadata, uploaded, bytes);
}

function r2ObjectFromSize(
  key: string,
  size: number,
  metadata: StoredMetadata,
  uploaded = new Date(metadata.uploaded),
  bytes?: Uint8Array,
): R2Object {
  const etag = bytes ? createHash("sha256").update(bytes).digest("hex") : `${size}-${uploaded.getTime()}`;
  return {
    key,
    version: etag,
    size,
    etag,
    httpEtag: `"${etag}"`,
    uploaded,
    httpMetadata: metadata.contentType ? { contentType: metadata.contentType } : undefined,
    customMetadata: metadata.customMetadata,
    storageClass: "Standard",
    checksums: { toJSON: () => ({}) },
    writeHttpMetadata(headers: Headers) {
      if (metadata.contentType) headers.set("Content-Type", metadata.contentType);
    },
  } as R2Object;
}

function r2ObjectBody(
  key: string,
  bytes: Uint8Array,
  metadata: StoredMetadata,
): R2ObjectBody {
  const base = r2Object(key, bytes, metadata);
  const blob = new Blob([bytes], { type: metadata.contentType });
  return {
    ...base,
    body: blob.stream(),
    bodyUsed: false,
    arrayBuffer: () => blob.arrayBuffer(),
    bytes: async () => new Uint8Array(await blob.arrayBuffer()),
    text: () => blob.text(),
    json: async <T>() => JSON.parse(await blob.text()) as T,
    blob: async () => blob,
  } as R2ObjectBody;
}

function isMissingFile(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "ENOENT";
}
