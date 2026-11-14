import { AIError, type ToolCall, type ToolLoopResult } from "./ai/provider.ts";
import { ASK_SYSTEM, askUserPrompt } from "./ai/prompts.ts";
import { checkDailyLimit, type Ctx, loadCategories, loadProfile, logUsage } from "./context.ts";
import { type Filters, parseFilters, parsePeriod } from "./query/filters.ts";
import { buildTools } from "./query/tools.ts";
import { AppError, type AskAnswer, type Category, type Evidence, type Profile } from "./types.ts";
import { localDate, localWeekday } from "./utils/dates.ts";

const nt = (n: number) => `NT$${Number(n).toLocaleString("en-US")}`;

/** 回答裡寫成金額的數字：NT$1,234、$1,234、1234 元。 */
export function amountsInAnswer(answer: string): number[] {
  const out: number[] = [];
  for (const m of answer.matchAll(/(?:NT\$|\$)\s*([\d,]+)/g)) out.push(Number(m[1].replace(/,/g, "")));
  for (const m of answer.matchAll(/([\d,]+)\s*(?:元|塊)/g)) out.push(Number(m[1].replace(/,/g, "")));
  return out.filter((n) => Number.isFinite(n));
}

/** 工具結果裡出現過的所有數字。 */
export function numbersInResults(calls: ToolCall[]): Set<number> {
  const found = new Set<number>();
  const walk = (v: unknown) => {
    if (typeof v === "number") found.add(v);
    else if (typeof v === "string" && /^\d+$/.test(v)) found.add(Number(v));
    else if (Array.isArray(v)) v.forEach(walk);
    else if (typeof v === "object" && v !== null) Object.values(v).forEach(walk);
  };
  calls.filter((c) => !c.is_error).forEach((c) => walk(c.result));
  return found;
}

/** 規格 6.4 的回查：回答中的金額必須都出現在工具結果裡。 */
export function answerIsGrounded(answer: string, calls: ToolCall[]): boolean {
  if (answer.trim() === "") return false;
  const allowed = numbersInResults(calls);
  return amountsInAnswer(answer).every((n) => allowed.has(n));
}

/** 回查沒過時改用的制式摘要：只把工具結果照實講出來。 */
export function templateSummary(calls: ToolCall[]): string {
  const ok = calls.filter((c) => !c.is_error);
  if (ok.length === 0) return "目前查不到相關的紀錄。";
  const lines = ok.map((c) => {
    const r = c.result as Record<string, unknown>;
    switch (c.name) {
      case "sum_transactions":
        return Number(r.count) === 0 ? "查不到符合條件的紀錄。" : `共 ${nt(Number(r.total))}，一共 ${r.count} 筆。`;
      case "group_transactions": {
        const groups = (r.groups as Array<{ key: string; total: number }> | undefined) ?? [];
        if (groups.length === 0) return "查不到符合條件的紀錄。";
        const top = [...groups].sort((a, b) => b.total - a.total).slice(0, 3)
          .map((g) => `${g.key} ${nt(g.total)}`).join("、");
        return `合計 ${nt(Number(r.total))}，最多的是：${top}。`;
      }
      case "list_transactions": {
        const list = (r.transactions as Array<{ item: string; amount: number; occurred_on: string }> | undefined) ?? [];
        if (list.length === 0) return "查不到符合條件的紀錄。";
        const head = list.slice(0, 3).map((t) => `${t.occurred_on} ${t.item} ${nt(t.amount)}`).join("、");
        return `找到 ${list.length} 筆：${head}${list.length > 3 ? " 等" : ""}。`;
      }
      case "compare_periods": {
        const a = r.period_a as { total: number };
        const b = r.period_b as { total: number };
        return `前一段 ${nt(a.total)}，後一段 ${nt(b.total)}，相差 ${nt(Number(r.abs_difference))}。`;
      }
      default:
        return "";
    }
  });
  return [...new Set(lines.filter(Boolean))].join("\n");
}

async function buildEvidence(ctx: Ctx, calls: ToolCall[]): Promise<Evidence[]> {
  const wanted: Array<{ tool: string; filters: Filters }> = [];
  for (const call of calls.filter((c) => !c.is_error)) {
    const input = call.input as Record<string, unknown>;
    try {
      const filters = parseFilters(input.filters);
      if (call.name === "compare_periods") {
        wanted.push({ tool: call.name, filters: { ...filters, ...parsePeriod(input.period_a, "period_a") } });
        wanted.push({ tool: call.name, filters: { ...filters, ...parsePeriod(input.period_b, "period_b") } });
      } else {
        wanted.push({ tool: call.name, filters });
      }
    } catch {
      // 參數不合法的呼叫本來就沒有結果，不列入依據。
    }
  }

  const seen = new Set<string>();
  const evidence: Evidence[] = [];
  for (const w of wanted) {
    const key = JSON.stringify(w.filters);
    if (seen.has(key)) continue;
    seen.add(key);
    const { data, error } = await ctx.db.rpc("q_sum", { filters: w.filters });
    if (error || !data) continue;
    evidence.push({
      tool: w.tool,
      filters: w.filters as Record<string, unknown>,
      count: Number(data.count),
      total: Number(data.total),
      transaction_ids: (data.transaction_ids ?? []) as string[],
    });
  }
  return evidence;
}

/**
 * 查帳流程。AI 只負責理解問題和解釋結果，數字全部來自資料庫。
 * profile 與 categories 可由呼叫端傳入（從 record 轉接過來時避免重讀）。
 */
export async function runAsk(
  question: string,
  ctx: Ctx,
  preloaded?: { profile: Profile; categories: Category[] },
): Promise<AskAnswer> {
  const q = question.trim();
  if (q.length === 0) throw new AppError(400, "invalid_input", "請輸入想問的問題。");
  if (q.length > 500) throw new AppError(400, "too_long", "問題太長了，請縮短到 500 字以內。");

  const profile = preloaded?.profile ?? await loadProfile(ctx);
  const categories = preloaded?.categories ?? await loadCategories(ctx);
  await checkDailyLimit(ctx, "ask", profile.timezone);

  const now = ctx.now();
  const user = askUserPrompt({
    today: localDate(now, profile.timezone),
    weekday: localWeekday(now, profile.timezone),
    timezone: profile.timezone,
    categories,
    question: q,
  });
  const tools = buildTools(ctx.db);

  let loop: ToolLoopResult | null = null;
  for (let attempt = 0; attempt < 2 && !loop; attempt++) {
    const started = performance.now();
    try {
      loop = await ctx.ai.generateWithTools({ system: ASK_SYSTEM, user, tools });
      await logUsage(ctx, "ask", loop.usage, performance.now() - started);
    } catch (err) {
      if (err instanceof AIError && !err.retryable) break;
    }
  }
  if (!loop) throw new AppError(502, "ai_failed", "現在沒辦法回答，請稍後再問一次。");

  const answer = answerIsGrounded(loop.text, loop.calls) ? loop.text : templateSummary(loop.calls);
  return { answer, evidence: await buildEvidence(ctx, loop.calls) };
}
