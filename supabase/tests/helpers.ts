// 整合測試共用：連本機 Supabase（supabase start），每個測試用全新的匿名使用者。
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.119.0";
import type { AIProvider, StructuredResult, Tool, ToolLoopResult } from "../functions/_shared/ai/provider.ts";
import type { Ctx } from "../functions/_shared/context.ts";
import type { Category, Config } from "../functions/_shared/types.ts";

const URL = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("API_URL");
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("ANON_KEY");
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");

/** 沒有設定本機 Supabase 時，整合測試整批略過。 */
export const NO_DB = !URL || !ANON || !SERVICE;

// supabase-js 會留著計時器，測試要關掉資源檢查。
export const dbTest = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: NO_DB, sanitizeOps: false, sanitizeResources: false, fn });

const opts = { auth: { persistSession: false, autoRefreshToken: false } };

export const admin = (): SupabaseClient => createClient(URL!, SERVICE!, opts);
export const anon = (): SupabaseClient => createClient(URL!, ANON!, opts);

export interface TestUser {
  id: string;
  db: SupabaseClient;
}

export async function newUser(): Promise<TestUser> {
  const { data, error } = await anon().auth.signInAnonymously();
  if (error || !data.session || !data.user) throw new Error(`匿名登入失敗：${error?.message}`);
  const db = createClient(URL!, ANON!, {
    ...opts,
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
  return { id: data.user.id, db };
}

/** 固定的「現在」：2026-11-15 12:30（台北）。 */
export const FIXED_AT = "2026-11-15T12:30:00+08:00";
export const TODAY = "2026-11-15";

export const DEFAULT_CONFIG: Config = { autoCommitMax: 10000, dailyLimitRecord: 100, dailyLimitAsk: 30 };

/** 照劇本回答的假 AI：測試只驗證後端規則，不依賴真實模型。 */
export class ScriptedAI implements AIProvider {
  structuredCalls = 0;
  toolCalls = 0;

  constructor(
    private structured: (user: string) => unknown,
    private withTools?: (tools: Tool[], user: string) => Promise<Omit<ToolLoopResult, "usage">>,
  ) {}

  generateStructured(req: { system: string; user: string; schema: Record<string, unknown> }): Promise<StructuredResult> {
    this.structuredCalls++;
    const output = this.structured(req.user);
    if (output instanceof Error) return Promise.reject(output);
    return Promise.resolve({ output, usage: { model: "scripted", input_tokens: 10, output_tokens: 5 } });
  }

  async generateWithTools(req: { system: string; user: string; tools: Tool[] }): Promise<ToolLoopResult> {
    this.toolCalls++;
    if (!this.withTools) throw new Error("這個測試沒有準備查帳劇本");
    const r = await this.withTools(req.tools, req.user);
    return { ...r, usage: { model: "scripted", input_tokens: 10, output_tokens: 5 } };
  }
}

export function ctxFor(user: TestUser, ai: AIProvider, config: Partial<Config> = {}): Ctx {
  return {
    db: user.db,
    admin: admin(),
    userId: user.id,
    ai,
    config: { ...DEFAULT_CONFIG, ...config },
    now: () => new Date(FIXED_AT),
  };
}

export async function categories(db: SupabaseClient): Promise<Record<string, Category>> {
  const { data, error } = await db.from("categories").select("id, name, kind, icon");
  if (error || !data) throw new Error("讀不到分類");
  return Object.fromEntries((data as Category[]).map((c) => [c.name, c]));
}

export interface SeedTx {
  type?: "expense" | "income";
  amount: number;
  occurred_on: string;
  item: string;
  merchant?: string | null;
  category: string;
  tags?: string[];
  nature?: "routine" | "one_off" | "recurring" | null;
  note?: string | null;
}

export async function seed(user: TestUser, rows: SeedTx[]): Promise<Array<Record<string, unknown>>> {
  const cats = await categories(user.db);
  const { data, error } = await user.db.from("transactions").insert(rows.map((r) => ({
    user_id: user.id,
    type: r.type ?? "expense",
    amount: r.amount,
    occurred_on: r.occurred_on,
    item: r.item,
    merchant: r.merchant ?? null,
    category_id: cats[r.category].id,
    category_source: "ai",
    tags: r.tags ?? [],
    nature: r.nature ?? null,
    note: r.note ?? null,
  }))).select("*");
  if (error || !data) throw new Error(`種子資料寫入失敗：${error?.message}`);
  return data;
}

export async function countTx(user: TestUser): Promise<number> {
  const { count } = await user.db.from("transactions").select("id", { count: "exact", head: true });
  return count ?? 0;
}

/** AI 回傳的一筆交易（測試用的簡寫）。 */
export function aiTx(over: Record<string, unknown>): Record<string, unknown> {
  return {
    type: "expense", amount: 0, occurred_on: TODAY, item: "", merchant: null, category: null,
    tags: [], nature: null, payment_method: null, missing_fields: [], ...over,
  };
}

export const record = (...transactions: Record<string, unknown>[]) => ({ intent: "record", transactions, hint: null });
