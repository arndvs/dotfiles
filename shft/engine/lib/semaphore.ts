export class Semaphore {
  private queue: Array<() => void> = [];
  private active = 0;

  constructor(private readonly maxConcurrent: number) {}

  async acquire(): Promise<void> {
    if (this.active < this.maxConcurrent) {
      this.active++;
      return;
    }
    let resolve: () => void;
    const promise = new Promise<void>((r) => { resolve = r; });
    this.queue.push(resolve!);
    return promise;
  }

  release(): void {
    this.active--;
    const next = this.queue.shift();
    if (next) {
      this.active++;
      next();
    }
  }

  async run<T>(fn: () => Promise<T>): Promise<T> {
    await this.acquire();
    try {
      return await fn();
    } finally {
      this.release();
    }
  }
}
