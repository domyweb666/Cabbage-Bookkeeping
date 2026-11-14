import type { ParsedTx } from "../types.ts";
import { addDays } from "../utils/dates.ts";
import { matchAmounts } from "./normalize.ts";
import { MISSING_LABELS } from "./validate.ts";

export const MAX_TX_PER_ENTRY = 5;
export const AUTO_COMMIT_DAYS_BACK = 7;

export interface AutoCommitInput {
  transactions: ParsedTx[];
  /** 每筆是否有可用的分類（已套用使用者規則之後）。 */
  hasCategory: boolean[];
  rawText: string;
  /** 使用者輸入當下、在使用者時區的日期。 */
  today: string;
  autoCommitEnabled: boolean;
  autoCommitMax: number;
}

function nt(n: number): string {
  return n.toLocaleString("en-US");
}

/**
 * 規格 6.3：回傳每一筆「不能直接入帳的原因」。
 * 所有筆的原因都是空陣列，才整批直接入帳；任一筆有原因，整個輸入都走確認。
 * 是否入帳完全由這裡決定，不採用模型自己回報的信心。
 */
export function autoCommitReasons(input: AutoCommitInput): string[][] {
  const { transactions, rawText, today } = input;
  const matched = matchAmounts(transactions.map((t) => t.amount), rawText);
  const earliest = addDays(today, -AUTO_COMMIT_DAYS_BACK);

  return transactions.map((tx, i) => {
    const reasons: string[] = [];

    if (tx.missing_fields.length > 0) {
      const labels = tx.missing_fields.map((f) => MISSING_LABELS[f] ?? f);
      reasons.push(`缺少${[...new Set(labels)].join("、")}`);
    }
    if (tx.type === "income") reasons.push("收入需要確認");

    if (tx.amount > 0) {
      if (tx.amount > input.autoCommitMax) reasons.push(`金額超過 ${nt(input.autoCommitMax)}`);
      if (!matched[i]) reasons.push("金額在原話裡對不上");
    }

    if (!input.hasCategory[i] && !tx.missing_fields.includes("category")) reasons.push("分類不確定");

    if (tx.occurred_on) {
      if (tx.occurred_on > today) reasons.push("日期在未來");
      else if (tx.occurred_on < earliest) reasons.push(`日期超過 ${AUTO_COMMIT_DAYS_BACK} 天前`);
    }

    if (transactions.length > MAX_TX_PER_ENTRY) reasons.push(`一次超過 ${MAX_TX_PER_ENTRY} 筆`);
    if (!input.autoCommitEnabled) reasons.push("已關閉直接入帳");

    return reasons;
  });
}
