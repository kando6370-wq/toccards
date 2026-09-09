export class BackgroundTaskRegistry {
  private readonly tasks = new Set<Promise<unknown>>();

  createExecutionContext(): ExecutionContext {
    return {
      waitUntil: (promise: Promise<unknown>) => {
        const tracked = Promise.resolve(promise)
          .catch((error) => {
            console.error("Linux background task failed.", error);
          })
          .finally(() => {
            this.tasks.delete(tracked);
          });
        this.tasks.add(tracked);
      },
      passThroughOnException() {},
      props: {},
    } as unknown as ExecutionContext;
  }

  async drain(): Promise<void> {
    await Promise.allSettled([...this.tasks]);
  }
}
