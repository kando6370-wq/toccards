const ULID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

export function createId(now = new Date()): string {
  const bytes = new Uint8Array(16);
  const timestamp = now.getTime();

  bytes[0] = Math.floor(timestamp / 2 ** 40) & 0xff;
  bytes[1] = Math.floor(timestamp / 2 ** 32) & 0xff;
  bytes[2] = Math.floor(timestamp / 2 ** 24) & 0xff;
  bytes[3] = Math.floor(timestamp / 2 ** 16) & 0xff;
  bytes[4] = Math.floor(timestamp / 2 ** 8) & 0xff;
  bytes[5] = timestamp & 0xff;
  crypto.getRandomValues(bytes.subarray(6));

  return encodeUlid(bytes);
}

function encodeUlid(bytes: Uint8Array): string {
  return [
    ULID_ALPHABET[(bytes[0] & 224) >> 5],
    ULID_ALPHABET[bytes[0] & 31],
    ULID_ALPHABET[(bytes[1] & 248) >> 3],
    ULID_ALPHABET[((bytes[1] & 7) << 2) | ((bytes[2] & 192) >> 6)],
    ULID_ALPHABET[(bytes[2] & 62) >> 1],
    ULID_ALPHABET[((bytes[2] & 1) << 4) | ((bytes[3] & 240) >> 4)],
    ULID_ALPHABET[((bytes[3] & 15) << 1) | ((bytes[4] & 128) >> 7)],
    ULID_ALPHABET[(bytes[4] & 124) >> 2],
    ULID_ALPHABET[((bytes[4] & 3) << 3) | ((bytes[5] & 224) >> 5)],
    ULID_ALPHABET[bytes[5] & 31],
    ULID_ALPHABET[(bytes[6] & 248) >> 3],
    ULID_ALPHABET[((bytes[6] & 7) << 2) | ((bytes[7] & 192) >> 6)],
    ULID_ALPHABET[(bytes[7] & 62) >> 1],
    ULID_ALPHABET[((bytes[7] & 1) << 4) | ((bytes[8] & 240) >> 4)],
    ULID_ALPHABET[((bytes[8] & 15) << 1) | ((bytes[9] & 128) >> 7)],
    ULID_ALPHABET[(bytes[9] & 124) >> 2],
    ULID_ALPHABET[((bytes[9] & 3) << 3) | ((bytes[10] & 224) >> 5)],
    ULID_ALPHABET[bytes[10] & 31],
    ULID_ALPHABET[(bytes[11] & 248) >> 3],
    ULID_ALPHABET[((bytes[11] & 7) << 2) | ((bytes[12] & 192) >> 6)],
    ULID_ALPHABET[(bytes[12] & 62) >> 1],
    ULID_ALPHABET[((bytes[12] & 1) << 4) | ((bytes[13] & 240) >> 4)],
    ULID_ALPHABET[((bytes[13] & 15) << 1) | ((bytes[14] & 128) >> 7)],
    ULID_ALPHABET[(bytes[14] & 124) >> 2],
    ULID_ALPHABET[((bytes[14] & 3) << 3) | ((bytes[15] & 224) >> 5)],
    ULID_ALPHABET[bytes[15] & 31],
  ].join("");
}
