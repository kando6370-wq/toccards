import type { Editor, FieldIssue, SubscriptionRequest } from "./model";

export type PendingOperation = {
  version: 1; kind: "create" | "save" | "activate"; path: string; method: "POST" | "PUT";
  body: Record<string, unknown> & { request_id: string }; editor: Editor | null; baseline: string;
};
export type MutationFailure = { code: string; message: string; status?: number; fields?: FieldIssue[] };
export type MutationResult = { sequence: number; operation: PendingOperation; data?: unknown; error?: MutationFailure };
export type MutationState = {
  phase: "idle" | "submitting" | "checking" | "unknown" | "succeeded" | "failed";
  pending: PendingOperation | null; result: MutationResult | null; warning: string | null;
};
type MutationStatus = {
  request_id: string; status: "unknown" | "succeeded" | "failed"; http_status?: number;
  response?: { success: boolean; data?: unknown; error?: MutationFailure };
};
type Storage = { getItem(key: string): string | null; setItem(key: string, value: string): void; removeItem(key: string): void };
type Dependencies = {
  request: SubscriptionRequest; storage: Storage; key: string;
  writeMs?: number; checkMs?: number; pollMs?: number;
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parsePendingOperation(value: string | null): PendingOperation | null {
  if (value === null) return null;
  const op = JSON.parse(value) as PendingOperation;
  const pathValid = (op.kind === "create" && op.method === "POST" && op.path === "/subscription-configs") ||
    (op.kind === "save" && op.method === "PUT" && /^\/subscription-configs\/[0-9A-HJKMNP-TV-Z]{26}$/.test(op.path)) ||
    (op.kind === "activate" && op.method === "PUT" && /^\/subscription-configs\/active\/(page|modal)$/.test(op.path));
  if (op.version !== 1 || !pathValid || !op.body || !UUID.test(op.body.request_id) || typeof op.baseline !== "string") {
    throw new Error("无法读取原操作记录，请保留当前页面并联系支持，勿重复提交。");
  }
  if (op.kind !== "activate" && (!op.editor || !op.editor.body || !Array.isArray(op.editor.body.skus) ||
      typeof op.editor.body.name !== "string" || op.editor.body.schema_version !== 1)) {
    throw new Error("原操作的编辑记录不完整，请保留记录并联系支持。");
  }
  return op;
}

export class SubscriptionMutation {
  private dependencies: Dependencies;
  private listeners = new Set<(state: MutationState) => void>();
  private generation = 0;
  private controller: AbortController | null = null;
  private sequence = 0;
  private invalidStorage = false;
  state: MutationState;

  constructor(dependencies: Dependencies) {
    this.dependencies = dependencies;
    this.state = { phase: "idle", pending: null, result: null, warning: null };
    try {
      const pending = parsePendingOperation(dependencies.storage.getItem(dependencies.key));
      if (pending) this.state = { ...this.state, phase: "unknown", pending };
    } catch (error) {
      this.invalidStorage = true;
      this.state = { ...this.state, warning: failure(error).message };
    }
  }

  subscribe(listener: (state: MutationState) => void): () => void {
    this.listeners.add(listener); listener(this.state);
    return () => { this.listeners.delete(listener); };
  }

  async start(operation: PendingOperation): Promise<void> {
    if (this.state.pending || this.busy || this.invalidStorage) return;
    const snapshot = structuredClone(operation);
    try {
      parsePendingOperation(JSON.stringify(snapshot));
      this.dependencies.storage.setItem(this.dependencies.key, JSON.stringify(snapshot));
    } catch {
      this.publish({ ...this.state, phase: "failed", warning: "浏览器无法保存原操作记录，本次未发送请求。请检查会话存储后重试。" });
      return;
    }
    this.publish({ phase: "submitting", pending: snapshot, result: null, warning: null });
    const run = this.begin();
    await this.send(snapshot, run);
  }

  async reconcile(replay = false): Promise<void> {
    const operation = this.state.pending;
    if (!operation || this.busy) return;
    const run = this.begin();
    this.publish({ ...this.state, phase: "checking", warning: null });
    if (!replay) { await this.check(operation, run); return; }
    const writeUntil = Date.now() + (this.dependencies.writeMs ?? 15_000);
    try {
      const result = await this.lookup(operation, Math.max(1, writeUntil - Date.now()));
      if (!this.current(run)) return;
      if (this.confirm(operation, result)) return;
      // A missing result is unknown, never proof of failure. Replay only the exact
      // persisted request, after reconciliation, so the server can deduplicate it.
      const remaining = writeUntil - Date.now();
      if (remaining <= 0) { this.unknown(); return; }
      await this.send(operation, run, true, remaining);
    } catch (error) { if (this.current(run)) this.unknown(error); }
  }

  stop(): void {
    this.generation += 1;
    this.controller?.abort();
    this.controller = null;
    if (this.state.pending) this.publish({ ...this.state, phase: "unknown" });
  }

  get busy(): boolean { return this.state.phase === "submitting" || this.state.phase === "checking"; }
  get blocked(): boolean { return this.busy || !!this.state.pending || this.invalidStorage; }

  private begin(): number {
    this.controller?.abort();
    this.controller = new AbortController();
    return ++this.generation;
  }
  private current(run: number): boolean { return run === this.generation && !this.controller?.signal.aborted; }
  private publish(state: MutationState): void {
    this.state = state;
    for (const listener of this.listeners) listener(state);
  }
  private async send(operation: PendingOperation, run: number, replay = false, writeMs = this.dependencies.writeMs ?? 15_000): Promise<void> {
    if (!this.current(run)) return;
    this.publish({ ...this.state, phase: "submitting" });
    try {
      const data = await deadline((signal) => this.dependencies.request(operation.path, {
        method: operation.method, body: operation.body, signal,
      }), writeMs, this.controller!.signal);
      if (this.current(run)) this.complete(operation, { data });
    } catch (error) {
      if (!this.current(run)) return;
      const rejected = failure(error);
      if (!replay && rejected.status && rejected.status >= 400 && rejected.status < 500 && !["REQUEST_FAILED", "IDEMPOTENCY_CONFLICT", "UNAUTHORIZED", "FORBIDDEN"].includes(rejected.code)) {
        this.complete(operation, { error: rejected });
      } else {
        this.publish({ ...this.state, phase: "checking" });
        await this.check(operation, run);
      }
    }
  }
  private async lookup(operation: PendingOperation, ms: number): Promise<MutationStatus> {
    return deadline((signal) => this.dependencies.request<MutationStatus>(
      "/subscription-config-mutations/" + operation.body.request_id, { signal },
    ), ms, this.controller!.signal);
  }
  private async check(operation: PendingOperation, run: number): Promise<void> {
    const until = Date.now() + (this.dependencies.checkMs ?? 15_000);
    try {
      while (this.current(run) && Date.now() < until) {
        const status = await this.lookup(operation, Math.max(1, until - Date.now()));
        if (!this.current(run)) return;
        if (this.confirm(operation, status)) return;
        await pause(Math.min(this.dependencies.pollMs ?? 1000, Math.max(0, until - Date.now())), this.controller!.signal);
      }
      if (this.current(run)) this.unknown();
    } catch (error) { if (this.current(run)) this.unknown(error); }
  }
  private confirm(operation: PendingOperation, status: MutationStatus): boolean {
    if (status?.request_id !== operation.body.request_id) throw new Error("操作核对响应不匹配");
    if (status.status === "unknown") return false;
    const response = status.response;
    if (status.status === "succeeded" && response?.success === true && status.http_status && status.http_status < 400) {
      this.complete(operation, { data: response.data }); return true;
    }
    if (status.status === "failed" && response?.success === false && response.error && status.http_status && status.http_status >= 400) {
      this.complete(operation, { error: { ...response.error, status: status.http_status } }); return true;
    }
    throw new Error("操作结果暂时无法确认");
  }
  private unknown(error?: unknown): void {
    const detail = error ? failure(error) : null;
    this.publish({ ...this.state, phase: "unknown", warning: detail?.code === "FORBIDDEN" || detail?.code === "UNAUTHORIZED"
      ? "请使用原操作账号重新登录后核对结果。" : "暂时无法确认操作结果，请稍后重试。当前输入和原请求已保留，可以离开。" });
  }
  private complete(operation: PendingOperation, outcome: { data?: unknown; error?: MutationFailure }): void {
    let warning: string | null = null;
    try { this.dependencies.storage.removeItem(this.dependencies.key); }
    catch { warning = "操作结果已确认，但浏览器未能清除核对记录；重新进入时将再次核对，不能重复计为新操作。"; }
    this.publish({ phase: outcome.error ? "failed" : "succeeded", pending: null, warning,
      result: { sequence: ++this.sequence, operation, ...outcome } });
  }
}

function failure(error: unknown): MutationFailure {
  const value = error && typeof error === "object" ? error as Record<string, unknown> : {};
  return { code: typeof value.code === "string" ? value.code : "UNKNOWN_RESULT",
    message: typeof value.message === "string" ? value.message : "网络请求失败，结果暂时无法确认。",
    ...(typeof value.status === "number" ? { status: value.status } : {}),
    ...(Array.isArray(value.fields) ? { fields: value.fields as FieldIssue[] } : {}) };
}
function deadline<T>(run: (signal: AbortSignal) => Promise<T>, ms: number, parent: AbortSignal): Promise<T> {
  return new Promise((resolve, reject) => {
    const controller = new AbortController();
    let settled = false;
    const finish = (result: { value: T } | { error: Error }) => {
      if (settled) return;
      settled = true; clearTimeout(timer); parent.removeEventListener("abort", abort);
      if ("error" in result) reject(result.error); else resolve(result.value);
    };
    const abort = () => { controller.abort(); finish({ error: new Error("Request canceled") }); };
    const timer = setTimeout(() => { controller.abort(); finish({ error: new Error("Request timed out") }); }, ms);
    parent.addEventListener("abort", abort, { once: true });
    if (parent.aborted) abort();
    Promise.resolve().then(() => {
      if (controller.signal.aborted) throw new Error("Request canceled");
      return run(controller.signal);
    }).then((value) => finish({ value }), (error: Error) => finish({ error }));
  });
}
function pause(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(new Error("Request canceled")); };
    const timer = setTimeout(() => { signal.removeEventListener("abort", abort); resolve(); }, ms);
    signal.addEventListener("abort", abort, { once: true });
    if (signal.aborted) abort();
  });
}
