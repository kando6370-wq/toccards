export function createHttpVectorRecognition(
  baseUrl: string,
  timeoutMs = 10_000,
): Fetcher {
  let origin: URL;
  const configurationError = "VECTOR_RECOGNITION_BASE_URL must be an HTTP(S) origin without credentials, path, query or fragment";
  try {
    origin = new URL(baseUrl);
  } catch {
    throw new Error(configurationError);
  }
  if (
    !["http:", "https:"].includes(origin.protocol) ||
    origin.username || origin.password || origin.pathname !== "/" ||
    origin.search || origin.hash
  ) {
    throw new Error(configurationError);
  }
  const endpoint = new URL("/recognize", origin).toString();

  return {
    fetch(_input: RequestInfo | URL, init: RequestInit = {}) {
      const timeout = AbortSignal.timeout(timeoutMs);
      const signal = init.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
      // The caller's Service Binding URL is internal to Workers, not a Linux origin.
      return fetch(endpoint, { ...init, signal, redirect: "error" });
    },
  } as unknown as Fetcher;
}
