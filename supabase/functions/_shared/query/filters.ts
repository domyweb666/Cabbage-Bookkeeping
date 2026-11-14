import { isValidDate } from "../utils/dates.ts";

// 查帳工具的 filters 白名單（規格 6.4）。模型給的參數一律先過這裡，
// 沒列出的欄位直接丟掉、型別不對就拒絕，之後才交給資料庫的參數化查詢。

export interface Filters {
  date_from?: string;
  date_to?: string;
  type?: "expense" | "income";
  categories?: string[];
  tags?: string[];
  nature?: "routine" | "one_off" | "recurring";
  merchant_contains?: string;
  text_contains?: string;
  amount_min?: number;
  amount_max?: number;
}

export class FilterError extends Error {}

function text(v: unknown, name: string): string | undefined {
  if (v === null || v === undefined || v === "") return undefined;
  if (typeof v !== "string") throw new FilterError(`${name} 必須是文字`);
  const t = v.trim();
  if (t.length > 50) throw new FilterError(`${name} 太長`);
  return t === "" ? undefined : t;
}

function date(v: unknown, name: string): string | undefined {
  if (v === null || v === undefined || v === "") return undefined;
  if (!isValidDate(v)) throw new FilterError(`${name} 必須是 YYYY-MM-DD`);
  return v;
}

function amount(v: unknown, name: string): number | undefined {
  if (v === null || v === undefined) return undefined;
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0) throw new FilterError(`${name} 必須是非負整數`);
  return v;
}

function list(v: unknown, name: string): string[] | undefined {
  if (v === null || v === undefined) return undefined;
  if (!Array.isArray(v) || v.some((x) => typeof x !== "string")) throw new FilterError(`${name} 必須是文字陣列`);
  const out = (v as string[]).map((x) => x.trim()).filter(Boolean).slice(0, 12);
  return out.length === 0 ? undefined : out;
}

export function parseFilters(raw: unknown): Filters {
  if (raw === null || raw === undefined) return {};
  if (typeof raw !== "object" || Array.isArray(raw)) throw new FilterError("filters 必須是物件");
  const o = raw as Record<string, unknown>;
  const out: Filters = {};

  const from = date(o.date_from, "date_from");
  const to = date(o.date_to, "date_to");
  if (from && to && from > to) throw new FilterError("date_from 不能晚於 date_to");
  if (from) out.date_from = from;
  if (to) out.date_to = to;

  if (o.type !== null && o.type !== undefined) {
    if (o.type !== "expense" && o.type !== "income") throw new FilterError("type 只能是 expense 或 income");
    out.type = o.type;
  }
  if (o.nature !== null && o.nature !== undefined) {
    if (o.nature !== "routine" && o.nature !== "one_off" && o.nature !== "recurring") {
      throw new FilterError("nature 只能是 routine、one_off、recurring");
    }
    out.nature = o.nature;
  }

  const categories = list(o.categories, "categories");
  if (categories) out.categories = categories;
  const tags = list(o.tags, "tags");
  if (tags) out.tags = tags;

  const merchant = text(o.merchant_contains, "merchant_contains");
  if (merchant) out.merchant_contains = merchant;
  const contains = text(o.text_contains, "text_contains");
  if (contains) out.text_contains = contains;

  const min = amount(o.amount_min, "amount_min");
  const max = amount(o.amount_max, "amount_max");
  if (min !== undefined) out.amount_min = min;
  if (max !== undefined) out.amount_max = max;

  return out;
}

export function parsePeriod(raw: unknown, name: string): { date_from: string; date_to: string } {
  if (typeof raw !== "object" || raw === null) throw new FilterError(`${name} 必須是物件`);
  const o = raw as Record<string, unknown>;
  const from = date(o.date_from, `${name}.date_from`);
  const to = date(o.date_to, `${name}.date_to`);
  if (!from || !to) throw new FilterError(`${name} 需要 date_from 與 date_to`);
  if (from > to) throw new FilterError(`${name} 的 date_from 不能晚於 date_to`);
  return { date_from: from, date_to: to };
}

/** 給模型看的 filters 說明（JSON Schema）。 */
export const FILTERS_SCHEMA = {
  type: "object",
  description: "篩選條件，全部選填。沒給就是不限制。",
  properties: {
    date_from: { type: "string", description: "起始日（含），YYYY-MM-DD" },
    date_to: { type: "string", description: "結束日（含），YYYY-MM-DD" },
    type: { type: "string", enum: ["expense", "income"], description: "支出或收入；問花費時填 expense" },
    categories: { type: "array", items: { type: "string" }, description: "分類名稱，只能用可用分類清單裡的" },
    tags: { type: "array", items: { type: "string" }, description: "標籤，命中任一個就算，例如 外食、宵夜" },
    nature: { type: "string", enum: ["routine", "one_off", "recurring"], description: "日常、一次性、固定" },
    merchant_contains: { type: "string", description: "商家名稱包含這段文字" },
    text_contains: { type: "string", description: "品項、商家、備註或原話包含這段文字" },
    amount_min: { type: "integer", description: "金額下限（含）" },
    amount_max: { type: "integer", description: "金額上限（含）" },
  },
} as const;
