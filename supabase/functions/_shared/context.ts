import type { SupabaseClient } from "npm:@supabase/supabase-js@2.119.0";
import type { AIProvider, Usage } from "./ai/provider.ts";
import { AppError, type Category, type Config, type Profile } from "./types.ts";
import { localDate, startOfLocalDay } from "./utils/dates.ts";

/** 一次請求的執行環境。測試時可以整個換掉（假 AI、固定時間）。 */
export interface Ctx {
  /** 帶著使用者 JWT 的連線，所有讀寫都受 RLS 限制。 */
  db: SupabaseClient;
  /** service role 連線，只用來寫 ai_usage。 */
  admin: SupabaseClient | null;
  userId: string;
  ai: AIProvider;
  config: Config;
  now: () => Date;
}

export async function loadProfile(ctx: Ctx): Promise<Profile> {
  const { data, error } = await ctx.db.from("profiles").select("id, currency, timezone, auto_commit")
    .eq("id", ctx.userId).maybeSingle();
  if (error) throw new AppError(500, "db_error", "讀取設定失敗，請稍後再試");
  // 理論上註冊時就會建立；保險起見沒有就用預設值。
  return data ?? { id: ctx.userId, currency: "TWD", timezone: "Asia/Taipei", auto_commit: true };
}

export async function loadCategories(ctx: Ctx): Promise<Category[]> {
  const { data, error } = await ctx.db.from("categories").select("id, name, kind, icon").order("sort_order");
  if (error || !data) throw new AppError(500, "db_error", "讀取分類失敗，請稍後再試");
  return data as Category[];
}

/** 檢查每日用量上限（以使用者時區的「今天」計）。 */
export async function checkDailyLimit(ctx: Ctx, feature: "record" | "ask", timezone: string): Promise<void> {
  const limit = feature === "record" ? ctx.config.dailyLimitRecord : ctx.config.dailyLimitAsk;
  const since = startOfLocalDay(localDate(ctx.now(), timezone), timezone);
  const { count, error } = await ctx.db.from("ai_usage").select("id", { count: "exact", head: true })
    .eq("user_id", ctx.userId).eq("feature", feature).gte("created_at", since.toISOString());
  if (error) throw new AppError(500, "db_error", "讀取用量失敗，請稍後再試");
  if ((count ?? 0) >= limit) {
    const what = feature === "record" ? "記帳" : "提問";
    throw new AppError(429, "daily_limit", `今天的${what}次數已達上限（${limit} 次），明天就會恢復。`);
  }
}

export async function logUsage(ctx: Ctx, feature: "record" | "ask", usage: Usage, latencyMs: number): Promise<void> {
  if (!ctx.admin) return;
  await ctx.admin.from("ai_usage").insert({
    user_id: ctx.userId,
    feature,
    model: usage.model,
    input_tokens: usage.input_tokens,
    output_tokens: usage.output_tokens,
    latency_ms: Math.round(latencyMs),
  });
}
