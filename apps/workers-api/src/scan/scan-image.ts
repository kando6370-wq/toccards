const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const MIN_IMAGE_SIDE = 256;
const MAX_IMAGE_SIDE = 1600;
const MAX_IMAGE_PIXELS = 2_000_000;

export type ValidatedScanImage = {
  bytes: Uint8Array;
  contentType: "image/jpeg" | "image/webp";
  extension: "jpg" | "webp";
  width: number;
  height: number;
};

export async function validateScanImage(value: string | File | null): Promise<ValidatedScanImage | null> {
  if (!(value instanceof File) || value.size === 0 || value.size > MAX_IMAGE_BYTES) return null;
  if (value.type !== "image/jpeg" && value.type !== "image/webp") return null;
  const bytes = new Uint8Array(await value.arrayBuffer());
  const dimensions = value.type === "image/jpeg" ? jpegDimensions(bytes) : webpDimensions(bytes);
  if (!dimensions) return null;
  const { width, height } = dimensions;
  if (
    width < MIN_IMAGE_SIDE || height < MIN_IMAGE_SIDE ||
    width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE ||
    width * height > MAX_IMAGE_PIXELS
  ) return null;
  return {
    bytes,
    contentType: value.type,
    extension: value.type === "image/jpeg" ? "jpg" : "webp",
    width,
    height,
  };
}

function jpegDimensions(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes.length < 10 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  const startOfFrame = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
  let offset = 2;
  while (offset + 8 < bytes.length) {
    if (bytes[offset] !== 0xff) return null;
    while (offset < bytes.length && bytes[offset] === 0xff) offset += 1;
    const marker = bytes[offset++];
    if (marker === 0xd9 || marker === 0xda) return null;
    if (marker >= 0xd0 && marker <= 0xd7) continue;
    if (offset + 1 >= bytes.length) return null;
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return null;
    if (startOfFrame.has(marker)) {
      if (length < 7) return null;
      const height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      const width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      return width > 0 && height > 0 ? { width, height } : null;
    }
    offset += length;
  }
  return null;
}

function webpDimensions(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes.length < 30 || ascii(bytes, 0, 4) !== "RIFF" || ascii(bytes, 8, 4) !== "WEBP") return null;
  const chunk = ascii(bytes, 12, 4);
  if (chunk === "VP8X") {
    return { width: readUint24(bytes, 24) + 1, height: readUint24(bytes, 27) + 1 };
  }
  if (chunk === "VP8 " && bytes[23] === 0x9d && bytes[24] === 0x01 && bytes[25] === 0x2a) {
    return {
      width: (bytes[26] | (bytes[27] << 8)) & 0x3fff,
      height: (bytes[28] | (bytes[29] << 8)) & 0x3fff,
    };
  }
  if (chunk === "VP8L" && bytes[20] === 0x2f) {
    const bits = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
    return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
  }
  return null;
}

function ascii(bytes: Uint8Array, offset: number, length: number): string {
  return String.fromCharCode(...bytes.subarray(offset, offset + length));
}

function readUint24(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}
