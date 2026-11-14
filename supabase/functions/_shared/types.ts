export type TxType = "expense" | "income";
export type Nature = "routine" | "one_off" | "recurring";
export type Intent = "record" | "query" | "unclear";

/** AI 解析出來的一筆交易（尚未驗證）。 */
export interface ParsedTx {
  type: TxType;
  amount: number;
  occurred_on: string;
  item: string;
  merchant: string | null;
  category: string | null;
  tags: string[];
  nature: Nature | null;
  payment_method: string | null;
  missing_fields: string[];
}

export interface ParseOutput {
  intent: Intent;
  transactions: ParsedTx[];
  hint: string | null;
}

export interface Category {
  id: string;
  name: string;
  kind: TxType;
  icon: string;
}

export interface UserRule {
  id: string;
  match_text: string;
  category_id: string;
  hits: number;
}

export interface Profile {
  id: string;
  currency: string;
  timezone: string;
  auto_commit: boolean;
}

/** 等使用者確認的草稿。 */
export interface Draft {
  type: TxType;
  amount: number;
  occurred_on: string;
  item: string;
  merchant: string | null;
  category_id: string | null;
  category_name: string | null;
  category_source: "ai" | "rule";
  tags: string[];
  nature: Nature | null;
  payment_method: string | null;
  reasons: string[];
}

export interface Evidence {
  tool: string;
  filters: Record<string, unknown>;
  count: number;
  total: number;
  transaction_ids: string[];
}

export interface AskAnswer {
  answer: string;
  evidence: Evidence[];
}

export type RecordResult =
  | { result: "committed"; entry_id: string; transactions: Record<string, unknown>[] }
  | { result: "needs_confirm"; entry_id: string; drafts: Draft[] }
  | ({ result: "answer"; entry_id: string } & AskAnswer)
  | { result: "unclear"; entry_id: string; message: string }
  | { result: "cancelled"; entry_id: string };

export interface Config {
  autoCommitMax: number;
  dailyLimitRecord: number;
  dailyLimitAsk: number;
}

export class AppError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}
