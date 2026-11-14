import type { Category, ParsedTx, UserRule } from "../types.ts";
import { normalizeText } from "./normalize.ts";

export interface Classified {
  category: Category | null;
  source: "ai" | "rule";
  ruleId: string | null;
}

function key(s: string | null): string {
  return s ? normalizeText(s).trim().toLowerCase() : "";
}

/**
 * 決定一筆交易的分類。
 * 先比對使用者的修正規則（商家或品項含有關鍵字就命中），命中就覆蓋 AI 的分類並標記為 rule；
 * 沒命中才用 AI 給的分類，而且必須在可用清單內、收支類型要對得上。
 */
export function classify(tx: ParsedTx, categories: Category[], rules: UserRule[]): Classified {
  const merchant = key(tx.merchant);
  const item = key(tx.item);

  // 關鍵字長的優先，避免「全聯」蓋過「全聯藥局」。
  const sorted = [...rules].sort((a, b) => b.match_text.length - a.match_text.length);
  for (const rule of sorted) {
    const k = key(rule.match_text);
    if (!k) continue;
    if ((merchant && merchant.includes(k)) || (item && item.includes(k))) {
      const category = categories.find((c) => c.id === rule.category_id);
      if (category && category.kind === tx.type) {
        return { category, source: "rule", ruleId: rule.id };
      }
    }
  }

  if (tx.type === "income") {
    const income = categories.find((c) => c.kind === "income") ?? null;
    return { category: income, source: "ai", ruleId: null };
  }

  const byName = tx.category ? categories.find((c) => c.name === tx.category) : undefined;
  if (byName && byName.kind === tx.type) return { category: byName, source: "ai", ruleId: null };
  return { category: null, source: "ai", ruleId: null };
}
