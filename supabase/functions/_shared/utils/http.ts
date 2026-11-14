import { createClient } from "npm:@supabase/supabase-js@2.119.0";
import { AnthropicProvider } from "../ai/anthropic.ts";
import { MockProvider } from "../ai/mock.ts";
import type { AIProvider } from "../ai/provider.ts";
import type { Ctx } from "../context.ts";
import { AppError, type Config } from "../types.ts";

// 統一回傳格式（規格第 5 節）：{ success, data, error, request_id }

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function intEnv(name: string, fallback: number): number {
  const n = Number(Deno.env.get(name));
  return Number.isInteger(n) && n > 0 ? n : fallback;
}

function configFromEnv(): Config {
  return {
    autoCommitMax: intEnv("AUTO_COMMIT_MAX", 10000),
    dailyLimitRecord: intEnv("DAILY_LIMIT_RECORD", 100),
    dailyLimitAsk: intEnv("DAILY_LIMIT_ASK", 30),
  };
}

let cachedProvider: AIProvider | null = null;

function providerFromEnv(): AIProvider {
  if (cachedProvider) return cachedProvider;
  const name = (Deno.env.get("AI_PROVIDER") ?? "").toLowerCase();
  if (name === "mock") {
    cachedProvider = new MockProvider();
  } else if (name === "anthropic" || name === "claude") {
    const apiKey = Deno.env.get("AI_API_KEY");
    const modelRecord = Deno.env.get("AI_MODEL_RECORD");
    const modelAsk = Deno.env.get("AI_MODEL_ASK");
    if (!apiKey || !modelRecord || !modelAsk) throw new AppError(500, "not_configured", "服務尚未設定完成，請稍後再試。");
    cachedProvider = new AnthropicProvider({ apiKey, modelRecord, modelAsk });
  } else {
    throw new AppError(500, "not_configured", "服務尚未設定完成，請稍後再試。");
  }
  return cachedProvider;
}

/** 驗證 JWT 並建立這次請求的執行環境。user_id 一律取自 JWT，不接受前端傳入。 */
async function buildCtx(req: Request): Promise<Ctx> {
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) throw new AppError(401, "unauthorized", "請重新開啟 App 再試一次。");

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  const db = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) throw new AppError(401, "unauthorized", "登入已過期，請重新開啟 App 再試一次。");

  const admin = serviceKey
    ? createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
    : null;

  return { db, admin, userId: data.user.id, ai: providerFromEnv(), config: configFromEnv(), now: () => new Date() };
}

export type Handler = (body: unknown, ctx: Ctx, req: Request) => Promise<unknown>;

/** 把 handler 包成 Edge Function：驗證、解析 JSON、統一格式、錯誤不暴露內部細節。 */
export function serve(handler: Handler): void {
  Deno.serve(async (req) => {
    const requestId = crypto.randomUUID();
    const fail = (status: number, code: string, message: string) =>
      json(status, { success: false, data: null, error: { code, message }, request_id: requestId });

    if (req.method !== "POST") return fail(405, "method_not_allowed", "不支援這個請求方式。");
    try {
      const ctx = await buildCtx(req);
      let body: unknown;
      try {
        body = await req.json();
      } catch {
        throw new AppError(400, "invalid_input", "請求內容不是合法的 JSON。");
      }
      const data = await handler(body, ctx, req);
      return json(200, { success: true, data, error: null, request_id: requestId });
    } catch (err) {
      if (err instanceof AppError) return fail(err.status, err.code, err.message);
      console.error(`[${requestId}]`, err);
      return fail(500, "internal_error", "發生了一點問題，請稍後再試。");
    }
  });
}
