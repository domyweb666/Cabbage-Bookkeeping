import { AIError } from "./ai/provider.ts";
import { RECORD_SYSTEM, recordSchema, recordUserPrompt, topRulesForPrompt } from "./ai/prompts.ts";
import { runAsk } from "./ask.ts";
import { checkDailyLimit, type Ctx, loadCategories, loadProfile, logUsage } from "./context.ts";
import { autoCommitReasons } from "./rules/autocommit.ts";
import { classify } from "./rules/classify.ts";
import { MAX_AMOUNT, validateParseOutput } from "./rules/validate.ts";
import { AppError, type Category, type Draft, type ParseOutput, type RecordResult, type UserRule } from "./types.ts";
import { isValidDate, localDate } from "./utils/dates.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const STALE_PROCESSING_MS = 60_000;

export interface RecordInput {
  entry_id: string;
  raw_text: string;
  source: "text" | "voice";
  client_created_at: string;
}

function parseInput(body: unknown): RecordInput {
  const o = (typeof body === "object" && body !== null ? body : {}) as Record<string, unknown>;
  if (typeof o.entry_id !== "string" || !UUID_RE.test(o.entry_id)) {
    throw new AppError(400, "invalid_input", "entry_id 格式不正確。");
  }
  if (typeof o.raw_text !== "string" || o.raw_text.trim() === "") {
    throw new AppError(400, "invalid_input", "請輸入內容。");
  }
  const rawText = o.raw_text.trim();
  if ([...rawText].length > 500) throw new AppError(400, "too_long", "內容太長了，請縮短到 500 字以內。");
  if (o.source !== "text" && o.source !== "voice") throw new AppError(400, "invalid_input", "source 不正確。");
  if (typeof o.client_created_at !== "string" || Number.isNaN(new Date(o.client_created_at).getTime())) {
    throw new AppError(400, "invalid_input", "client_created_at 不正確。");
  }
  return { entry_id: o.entry_id.toLowerCase(), raw_text: rawText, source: o.source, client_created_at: o.client_created_at };
}

async function saveEntry(ctx: Ctx, entryId: string, patch: Record<string, unknown>): Promise<void> {
  const { error } = await ctx.db.from("entries").update(patch).eq("id", entryId);
  if (error) throw new AppError(500, "db_error", "儲存失敗，請稍後再試。");
}

/**
 * 先存原話（規格原則 3）。同一個 entry_id 重送時回傳第一次的結果，不重複寫入。
 * 回傳值不是 null 就代表已經有結果，直接回給前端。
 */
async function claimEntry(ctx: Ctx, input: RecordInput): Promise<RecordResult | null> {
  const inserted = await ctx.db.from("entries").insert({
    id: input.entry_id,
    user_id: ctx.userId,
    raw_text: input.raw_text,
    source: input.source,
    client_created_at: input.client_created_at,
    status: "processing",
  });
  if (!inserted.error) return null;
  if (inserted.error.code !== "23505") throw new AppError(500, "db_error", "儲存失敗，請稍後再試。");

  const { data: existing } = await ctx.db.from("entries")
    .select("status, result, created_at").eq("id", input.entry_id).maybeSingle();
  // 讀不到代表這個 id 屬於別人（RLS 擋掉）。
  if (!existing) throw new AppError(409, "entry_conflict", "這筆輸入的編號重複了，請重新輸入一次。");
  if (existing.result) return existing.result as RecordResult;
  if (existing.status === "failed") return null;
  const age = ctx.now().getTime() - new Date(existing.created_at).getTime();
  if (existing.status === "processing" && age > STALE_PROCESSING_MS) return null;
  throw new AppError(409, "processing", "這筆還在處理中，請稍等一下。");
}

async function parseWithAI(ctx: Ctx, system: string, user: string, schema: Record<string, unknown>): Promise<ParseOutput | null> {
  // 失敗時重試一次（規格 6.1）；格式不對也算失敗。
  for (let attempt = 0; attempt < 2; attempt++) {
    const started = performance.now();
    try {
      const res = await ctx.ai.generateStructured({ system, user, schema });
      await logUsage(ctx, "record", res.usage, performance.now() - started);
      const parsed = validateParseOutput(res.output);
      if (parsed) return parsed;
    } catch (err) {
      if (err instanceof AIError && !err.retryable) return null;
    }
  }
  return null;
}

export async function handleRecord(body: unknown, ctx: Ctx): Promise<RecordResult> {
  const input = parseInput(body);

  const previous = await claimEntry(ctx, input);
  if (previous) return previous;

  try {
    const profile = await loadProfile(ctx);
    const categories = await loadCategories(ctx);
    await checkDailyLimit(ctx, "record", profile.timezone);

    const { data: ruleRows } = await ctx.db.from("user_rules")
      .select("id, match_text, category_id, hits").order("hits", { ascending: false })
      .order("updated_at", { ascending: false }).limit(50);
    const rules = (ruleRows ?? []) as UserRule[];

    // 離線補送時 client_created_at 是當時記下的時間；裝置時間若在未來，以伺服器時間為準。
    const clientAt = new Date(input.client_created_at);
    const at = clientAt.getTime() > ctx.now().getTime() ? ctx.now() : clientAt;
    const today = localDate(at, profile.timezone);

    const parsed = await parseWithAI(
      ctx,
      RECORD_SYSTEM,
      recordUserPrompt({
        clientCreatedAt: at.toISOString(),
        timezone: profile.timezone,
        categories,
        rules: topRulesForPrompt(rules, categories),
        rawText: input.raw_text,
      }),
      recordSchema(categories.map((c) => c.name)),
    );
    if (!parsed) throw new AppError(502, "ai_failed", "現在沒辦法整理這筆，原話已經留著，可以稍後再試。");

    let result: RecordResult;
    let status: string;

    if (parsed.intent === "query") {
      const answer = await runAsk(input.raw_text, ctx, { profile, categories });
      result = { result: "answer", entry_id: input.entry_id, ...answer };
      status = "answered";
    } else if (parsed.intent === "unclear" || parsed.transactions.length === 0) {
      result = {
        result: "unclear",
        entry_id: input.entry_id,
        message: parsed.hint ?? "看不太懂這句，可以補上金額再試一次，例如「午餐 120」。",
      };
      status = "unclear";
      parsed.intent = "unclear";
    } else {
      const classified = parsed.transactions.map((tx) => classify(tx, categories, rules));
      const transactions = parsed.transactions.map((tx, i) => ({
        ...tx,
        // 規則已經補上分類的話，就不算缺分類。
        missing_fields: classified[i].category ? tx.missing_fields.filter((f) => f !== "category") : tx.missing_fields,
      }));
      const reasons = autoCommitReasons({
        transactions,
        hasCategory: classified.map((c) => c.category !== null),
        rawText: input.raw_text,
        today,
        autoCommitEnabled: profile.auto_commit,
        // 使用者可以把門檻調低；伺服器的 AUTO_COMMIT_MAX 是上限。
        autoCommitMax: Math.min(profile.auto_commit_max ?? ctx.config.autoCommitMax, ctx.config.autoCommitMax),
      });

      if (reasons.every((r) => r.length === 0)) {
        const rows = transactions.map((tx, i) => ({
          user_id: ctx.userId,
          entry_id: input.entry_id,
          type: tx.type,
          amount: tx.amount,
          currency: profile.currency,
          occurred_on: tx.occurred_on,
          item: tx.item,
          merchant: tx.merchant,
          category_id: classified[i].category!.id,
          category_source: classified[i].source,
          tags: tx.tags,
          nature: tx.nature,
          payment_method: tx.payment_method,
        }));
        const written = await ctx.db.from("transactions").insert(rows).select("*");
        if (written.error || !written.data) throw new AppError(500, "db_error", "寫入失敗，請稍後再試。");
        const ruleIds = classified.flatMap((c) => (c.ruleId ? [c.ruleId] : []));
        if (ruleIds.length > 0) await ctx.db.rpc("bump_rule_hits", { rule_ids: ruleIds });
        result = { result: "committed", entry_id: input.entry_id, transactions: written.data };
        status = "committed";
      } else {
        const drafts: Draft[] = transactions.map((tx, i) => ({
          type: tx.type,
          amount: tx.amount,
          occurred_on: tx.occurred_on || today,
          item: tx.item,
          merchant: tx.merchant,
          category_id: classified[i].category?.id ?? null,
          category_name: classified[i].category?.name ?? null,
          category_source: classified[i].source,
          tags: tx.tags,
          nature: tx.nature,
          payment_method: tx.payment_method,
          reasons: reasons[i],
        }));
        result = { result: "needs_confirm", entry_id: input.entry_id, drafts };
        status = "needs_confirm";
      }
    }

    await saveEntry(ctx, input.entry_id, { intent: parsed.intent, status, result });
    return result;
  } catch (err) {
    // 解析失敗也不丟原話：標成 failed，使用者可以用同一個 entry_id 再試。
    await ctx.db.from("entries").update({ status: "failed" }).eq("id", input.entry_id);
    throw err;
  }
}

// ───────────────────────── /record/confirm ─────────────────────────

interface ConfirmTx {
  type: "expense" | "income";
  amount: number;
  occurred_on: string;
  item: string;
  merchant: string | null;
  category_id: string;
  tags: string[];
  nature: "routine" | "one_off" | "recurring" | null;
  payment_method: string | null;
  note: string | null;
}

function optText(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t === "" ? null : t.slice(0, max);
}

function parseConfirmTx(raw: unknown, index: number, categories: Category[], today: string): ConfirmTx {
  const n = index + 1;
  const o = (typeof raw === "object" && raw !== null ? raw : {}) as Record<string, unknown>;
  if (o.type !== "expense" && o.type !== "income") throw new AppError(400, "invalid_input", `第 ${n} 筆的收支類型不正確。`);
  if (typeof o.amount !== "number" || !Number.isInteger(o.amount) || o.amount <= 0 || o.amount > MAX_AMOUNT) {
    throw new AppError(400, "invalid_input", `第 ${n} 筆的金額要是大於 0 的整數。`);
  }
  if (!isValidDate(o.occurred_on)) throw new AppError(400, "invalid_input", `第 ${n} 筆的日期不正確。`);
  if (o.occurred_on > today) throw new AppError(400, "invalid_input", `第 ${n} 筆的日期在未來，請改成今天或之前。`);
  const item = optText(o.item, 100);
  if (!item) throw new AppError(400, "invalid_input", `第 ${n} 筆需要填品項。`);
  const category = categories.find((c) => c.id === o.category_id);
  if (!category) throw new AppError(400, "invalid_input", `第 ${n} 筆需要選分類。`);
  if (category.kind !== o.type) throw new AppError(400, "invalid_input", `第 ${n} 筆的分類與收支類型對不上。`);
  const tags = Array.isArray(o.tags)
    ? [...new Set(o.tags.filter((t): t is string => typeof t === "string").map((t) => t.trim().slice(0, 20)).filter(Boolean))].slice(0, 5)
    : [];
  const nature = o.nature === "routine" || o.nature === "one_off" || o.nature === "recurring" ? o.nature : null;
  return {
    type: o.type,
    amount: o.amount,
    occurred_on: o.occurred_on,
    item,
    merchant: optText(o.merchant, 100),
    category_id: category.id,
    tags,
    nature,
    payment_method: optText(o.payment_method, 30),
    note: optText(o.note, 300),
  };
}

/** 送出使用者修正後的草稿：後端再驗證一次後寫入。cancel 為 true 時放棄這筆。 */
export async function handleConfirm(body: unknown, ctx: Ctx): Promise<RecordResult> {
  const o = (typeof body === "object" && body !== null ? body : {}) as Record<string, unknown>;
  if (typeof o.entry_id !== "string" || !UUID_RE.test(o.entry_id)) {
    throw new AppError(400, "invalid_input", "entry_id 格式不正確。");
  }
  const entryId = o.entry_id.toLowerCase();

  const { data: entry } = await ctx.db.from("entries").select("status, result").eq("id", entryId).maybeSingle();
  if (!entry) throw new AppError(404, "not_found", "找不到這筆待確認的輸入。");
  if (entry.status === "committed" || entry.status === "cancelled") return entry.result as RecordResult;
  if (entry.status !== "needs_confirm") throw new AppError(409, "not_confirmable", "這筆輸入目前不需要確認。");

  if (o.cancel === true) {
    const result: RecordResult = { result: "cancelled", entry_id: entryId };
    await saveEntry(ctx, entryId, { status: "cancelled", result });
    return result;
  }

  if (!Array.isArray(o.transactions) || o.transactions.length === 0) {
    throw new AppError(400, "invalid_input", "沒有要確認的交易。");
  }
  if (o.transactions.length > 20) throw new AppError(400, "invalid_input", "一次最多確認 20 筆。");

  const profile = await loadProfile(ctx);
  const categories = await loadCategories(ctx);
  const today = localDate(ctx.now(), profile.timezone);
  const drafts = ((entry.result as { drafts?: Draft[] } | null)?.drafts ?? []) as Draft[];
  const txs = o.transactions.map((t, i) => parseConfirmTx(t, i, categories, today));

  const rows = txs.map((tx, i) => {
    // 分類跟草稿一樣就沿用原本的來源；使用者改過就標成 user（之後會學成規則）。
    const draft = drafts.length === txs.length ? drafts[i] : undefined;
    const source = draft && draft.category_id === tx.category_id ? draft.category_source : "user";
    return { ...tx, user_id: ctx.userId, entry_id: entryId, currency: profile.currency, category_source: source };
  });

  const written = await ctx.db.from("transactions").insert(rows).select("*");
  if (written.error || !written.data) throw new AppError(500, "db_error", "寫入失敗，請稍後再試。");

  const result: RecordResult = { result: "committed", entry_id: entryId, transactions: written.data };
  await saveEntry(ctx, entryId, { status: "committed", result });
  return result;
}
