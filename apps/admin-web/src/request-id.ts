export const REQUEST_ID_HEADER = "X-Request-ID";

export function createAdminRequestHeaders(init?: HeadersInit): Headers {
  const headers = new Headers(init);
  headers.set(REQUEST_ID_HEADER, crypto.randomUUID());
  return headers;
}
