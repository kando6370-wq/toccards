const WorkerHeaders = Headers;
export { WorkerHeaders as Headers };

export type WorkerFetchInit = RequestInit & {
  timeout?: number;
};

export type WorkerFetchResponse = Response & {
  buffer(): Promise<Buffer>;
};

export default async function workerFetch(
  input: RequestInfo | URL,
  init: WorkerFetchInit = {},
): Promise<WorkerFetchResponse> {
  const { timeout, signal: existingSignal, ...nativeInit } = init;
  const timeoutMs = Number.isFinite(timeout) && timeout! > 0 ? timeout : null;
  if (timeoutMs === null) {
    return withBuffer(await fetch(input, { ...nativeInit, signal: existingSignal }));
  }

  const controller = new AbortController();
  const forwardAbort = () => controller.abort();
  if (existingSignal?.aborted) {
    controller.abort();
  } else {
    existingSignal?.addEventListener("abort", forwardAbort, { once: true });
  }
  const timer = setTimeout(() => {
    controller.abort();
    cleanup();
  }, timeoutMs);
  const cleanup = () => {
    clearTimeout(timer);
    existingSignal?.removeEventListener("abort", forwardAbort);
  };

  try {
    const response = await fetch(input, { ...nativeInit, signal: controller.signal });
    if (!response.ok) {
      cleanup();
      return withBuffer(response);
    }
    return withBuffer(response, cleanup);
  } catch (error) {
    cleanup();
    throw error;
  }
}

function withBuffer(response: Response, cleanup?: () => void): WorkerFetchResponse {
  Object.defineProperty(response, "buffer", {
    configurable: true,
    value: async () => {
      try {
        return Buffer.from(await response.arrayBuffer());
      } finally {
        cleanup?.();
      }
    },
  });
  return response as WorkerFetchResponse;
}
