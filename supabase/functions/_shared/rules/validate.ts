import type { Nature, ParsedTx, ParseOutput, TxType } from "../types.ts";
import { isValidDate } from "../utils/dates.ts";

const TYPES: TxType[] = ["expense", "income"];
const NATURES: Nature[] = ["routine", "one_off", "recurring"];
export const MAX_AMOUNT = 999_999_999;

function strOrNull(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t === "" ? null : t.slice(0, max);
}

/**
 * 驗證 AI 回傳的結構。格式不對就回 null（呼叫端會重試一次）。
 * 個別欄位缺漏不直接丟掉整筆，而是記在 missing_fields，交給確認卡處理。
 */
export function validateParseOutput(raw: unknown): ParseOutput | null {
  if (typeof raw !== "object" || raw === null) return null;
  const o = raw as Record<string, unknown>;
  if (o.intent !== "record" && o.intent !== "query" && o.intent !== "unclear") return null;
  const hint = strOrNull(o.hint, 200);
  if (o.intent !== "record") return { intent: o.intent, transactions: [], hint };
  if (!Array.isArray(o.transactions)) return null;

  const transactions: ParsedTx[] = [];
  for (const item of o.transactions) {
    if (typeof item !== "object" || item === null) return null;
    const t = item as Record<string, unknown>;
    if (!TYPES.includes(t.type as TxType)) return null;

    const missing = new Set<string>(
      Array.isArray(t.missing_fields)
        ? t.missing_fields.filter((m): m is string => typeof m === "string").map((m) => m.slice(0, 30))
        : [],
    );

    let amount = 0;
    if (typeof t.amount === "number" && Number.isInteger(t.amount) && t.amount > 0 && t.amount <= MAX_AMOUNT) {
      amount = t.amount;
    } else {
      missing.add("amount");
    }

    let occurredOn = "";
    if (isValidDate(t.occurred_on)) occurredOn = t.occurred_on;
    else missing.add("occurred_on");

    const itemName = strOrNull(t.item, 100) ?? strOrNull(t.merchant, 100);
    if (!itemName) missing.add("item");

    const tags = Array.isArray(t.tags)
      ? [...new Set(t.tags.filter((x): x is string => typeof x === "string").map((x) => x.trim().slice(0, 20)).filter(Boolean))]
        .slice(0, 3)
      : [];

    transactions.push({
      type: t.type as TxType,
      amount,
      occurred_on: occurredOn,
      item: itemName ?? "",
      merchant: strOrNull(t.merchant, 100),
      category: strOrNull(t.category, 30),
      tags,
      nature: NATURES.includes(t.nature as Nature) ? (t.nature as Nature) : null,
      payment_method: strOrNull(t.payment_method, 30),
      missing_fields: [...missing],
    });
  }
  return { intent: "record", transactions, hint };
}

export const MISSING_LABELS: Record<string, string> = {
  amount: "金額",
  occurred_on: "日期",
  item: "品項",
  category: "分類",
  type: "收支類型",
};
