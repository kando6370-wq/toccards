const PERIOD_MS = 60_000;
const MAX_IPS_PER_WINDOW = 10_000;

export function createExtensionRateLimiter(requestsPerMinute = 60): RateLimit {
  const counts = new Map<string, number>();
  let window = Math.floor(Date.now() / PERIOD_MS);
  return {
    async limit({ key }) {
      const currentWindow = Math.floor(Date.now() / PERIOD_MS);
      if (window !== currentWindow) {
        counts.clear();
        window = currentWindow;
      }
      const count = counts.get(key) ?? 0;
      // Do not evict active IPs: that would let an attacker reset their own counter.
      if (count >= requestsPerMinute || (count === 0 && counts.size >= MAX_IPS_PER_WINDOW)) {
        return { success: false };
      }
      counts.set(key, count + 1);
      return { success: true };
    },
  };
}
