// 日期處理一律明確指定時區。日期字串格式固定為 YYYY-MM-DD。

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/** 某個時間點在指定時區是哪一天。 */
export function localDate(at: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(at);
  const get = (t: string) => parts.find((p) => p.type === t)!.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

/** 指定時區的星期幾（中文）。 */
export function localWeekday(at: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("zh-TW", { timeZone, weekday: "long" }).format(at);
}

export function isValidDate(s: unknown): s is string {
  if (typeof s !== "string" || !DATE_RE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

/** 純日期加減天數（不涉及時區）。 */
export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** 指定時區某一天 00:00 對應的 UTC 時間點。 */
export function startOfLocalDay(date: string, timeZone: string): Date {
  // 先假設是 UTC 午夜，再用該時區的實際偏移修正。
  const guess = new Date(`${date}T00:00:00Z`);
  const asLocal = new Date(guess.toLocaleString("en-US", { timeZone }));
  const asUtc = new Date(guess.toLocaleString("en-US", { timeZone: "UTC" }));
  return new Date(guess.getTime() - (asLocal.getTime() - asUtc.getTime()));
}
