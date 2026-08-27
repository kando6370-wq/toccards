export type InstallationPeriod = "1d" | "7d" | "15d" | "1m" | "3m";

export const INSTALLATION_PERIOD_OPTIONS: InstallationPeriod[] = ["1d", "7d", "15d", "1m", "3m"];

const INSTALLATION_PERIOD_DAYS = { "1d": 1, "7d": 7, "15d": 15, "1m": 30, "3m": 90 } satisfies Record<InstallationPeriod, number>;

export function installationTrendForPeriod(
  data: Array<{ date: string; total: number }>,
  period: InstallationPeriod,
  filterEndDate: string,
  now = new Date(),
) {
  const endDate = /^\d{4}-\d{2}-\d{2}$/.test(filterEndDate) ? filterEndDate : now.toISOString().slice(0, 10);
  const start = new Date(`${endDate}T00:00:00.000Z`);
  start.setUTCDate(start.getUTCDate() - INSTALLATION_PERIOD_DAYS[period] + 1);
  const startDate = start.toISOString().slice(0, 10);
  return data.filter((item) => item.date >= startDate && item.date <= endDate);
}
