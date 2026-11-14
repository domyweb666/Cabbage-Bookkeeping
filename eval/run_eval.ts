// 解析評測（規格 1.5）：用固定測試集量正確率，不靠感覺。不需要資料庫。
//
//   AI_PROVIDER=anthropic AI_API_KEY=... AI_MODEL_RECORD=... AI_MODEL_ASK=... \
//     deno run --allow-env --allow-read --allow-write --allow-net eval/run_eval.ts
//
// 沒有金鑰時可用 AI_PROVIDER=mock 試跑流程（數字不代表真實模型）。
// 每跑一次會對 AI 服務發出約 110 次請求。
import { AnthropicProvider } from "../supabase/functions/_shared/ai/anthropic.ts";
import { MockProvider } from "../supabase/functions/_shared/ai/mock.ts";
import { RECORD_SYSTEM, recordSchema, recordUserPrompt } from "../supabase/functions/_shared/ai/prompts.ts";
import type { AIProvider } from "../supabase/functions/_shared/ai/provider.ts";
import { autoCommitReasons } from "../supabase/functions/_shared/rules/autocommit.ts";
import { classify } from "../supabase/functions/_shared/rules/classify.ts";
import { validateParseOutput } from "../supabase/functions/_shared/rules/validate.ts";
import type { Category, ParsedTx } from "../supabase/functions/_shared/types.ts";
import { localDate } from "../supabase/functions/_shared/utils/dates.ts";

const FIXED_AT = "2026-11-15T12:30:00+08:00";
const TIMEZONE = "Asia/Taipei";
const AUTO_COMMIT_MAX = Number(Deno.env.get("AUTO_COMMIT_MAX") ?? 10000);

const CATEGORIES: Category[] = [
  "飲食", "交通", "購物", "居住", "娛樂", "醫療", "學習", "訂閱", "旅行", "人情", "其他支出",
].map((name) => ({ id: name, name, kind: "expense" as const, icon: "" }))
  .concat([{ id: "收入", name: "收入", kind: "income" as const, icon: "" }] as never);

interface ExpectedTx {
  type: "expense" | "income";
  amount: number;
  date: string;
  category: string | string[];
  nature?: string;
}

interface Case {
  id: number;
  kind: string;
  input: string;
  intent: "record" | "query" | "unclear";
  result: string[];
  tx: ExpectedTx[];
}

interface Outcome {
  result: "committed" | "needs_confirm" | "answer" | "unclear" | "failed";
  tx: Array<ParsedTx & { finalCategory: string | null }>;
}

function provider(): AIProvider {
  const name = (Deno.env.get("AI_PROVIDER") ?? "").toLowerCase();
  if (name === "mock") return new MockProvider();
  const apiKey = Deno.env.get("AI_API_KEY");
  const modelRecord = Deno.env.get("AI_MODEL_RECORD");
  const modelAsk = Deno.env.get("AI_MODEL_ASK") ?? modelRecord;
  if (!apiKey || !modelRecord || !modelAsk) {
    console.error("需要 AI_API_KEY 與 AI_MODEL_RECORD（或設 AI_PROVIDER=mock 試跑）。");
    Deno.exit(2);
  }
  return new AnthropicProvider({ apiKey, modelRecord, modelAsk });
}

/** 跟 Edge Function 的 record 走同一套邏輯，只是不寫資料庫。 */
async function runCase(ai: AIProvider, c: Case): Promise<Outcome> {
  const at = new Date(FIXED_AT);
  const user = recordUserPrompt({
    clientCreatedAt: at.toISOString(), timezone: TIMEZONE, categories: CATEGORIES, rules: [], rawText: c.input,
  });
  let parsed = null;
  for (let attempt = 0; attempt < 2 && !parsed; attempt++) {
    try {
      const res = await ai.generateStructured({
        system: RECORD_SYSTEM, user, schema: recordSchema(CATEGORIES.map((x) => x.name)),
      });
      parsed = validateParseOutput(res.output);
    } catch {
      // 重試一次
    }
  }
  if (!parsed) return { result: "failed", tx: [] };
  if (parsed.intent === "query") return { result: "answer", tx: [] };
  if (parsed.intent === "unclear" || parsed.transactions.length === 0) return { result: "unclear", tx: [] };

  const classified = parsed.transactions.map((t) => classify(t, CATEGORIES, []));
  const reasons = autoCommitReasons({
    transactions: parsed.transactions,
    hasCategory: classified.map((x) => x.category !== null),
    rawText: c.input,
    today: localDate(at, TIMEZONE),
    autoCommitEnabled: true,
    autoCommitMax: AUTO_COMMIT_MAX,
  });
  return {
    result: reasons.every((r) => r.length === 0) ? "committed" : "needs_confirm",
    tx: parsed.transactions.map((t, i) => ({ ...t, finalCategory: classified[i].category?.name ?? null })),
  };
}

const sortKey = (t: { amount: number }) => t.amount;
const categoryOk = (expected: string | string[], actual: string | null) =>
  actual !== null && (Array.isArray(expected) ? expected.includes(actual) : expected === actual);

function score(c: Case, o: Outcome) {
  const expected = [...c.tx].sort((a, b) => sortKey(a) - sortKey(b));
  const actual = [...o.tx].sort((a, b) => sortKey(a) - sortKey(b));
  const sameCount = expected.length === actual.length;
  const amountOk = sameCount && expected.every((e, i) => e.amount === actual[i].amount);
  const typeDateOk = amountOk && expected.every((e, i) => e.type === actual[i].type && e.date === actual[i].occurred_on);
  const catOk = amountOk && expected.every((e, i) => categoryOk(e.category, actual[i].finalCategory));
  return {
    resultOk: c.result.includes(o.result),
    amountOk,
    typeDateOk,
    catOk,
    // 直接入帳的錯誤：系統入帳了，但金額、收支類型或日期有錯，或這句根本不該直接入帳。
    wrongCommit: o.result === "committed" && (!c.result.includes("committed") || !typeDateOk),
    questionRecorded: c.intent === "query" && (o.result === "committed" || o.result === "needs_confirm"),
  };
}

const pct = (n: number, d: number) => (d === 0 ? "—" : `${((n / d) * 100).toFixed(1)}%`);

const here = new URL(".", import.meta.url);
const cases: Case[] = (await Deno.readTextFile(new URL("parse_cases.jsonl", here)))
  .split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l));

const ai = provider();
const rows: Array<{ c: Case; o: Outcome; s: ReturnType<typeof score> }> = [];
const CONCURRENCY = 4;
for (let i = 0; i < cases.length; i += CONCURRENCY) {
  const batch = cases.slice(i, i + CONCURRENCY);
  const outcomes = await Promise.all(batch.map((c) => runCase(ai, c)));
  batch.forEach((c, j) => rows.push({ c, o: outcomes[j], s: score(c, outcomes[j]) }));
  await Deno.stdout.write(new TextEncoder().encode(`\r${rows.length}/${cases.length}`));
}
console.log();

const withTx = rows.filter((r) => r.c.tx.length > 0);
const committed = rows.filter((r) => r.o.result === "committed");
const metrics = [
  ["金額解析正確率", withTx.filter((r) => r.s.amountOk).length, withTx.length, "≥ 99%"],
  ["收支類型與日期正確率", withTx.filter((r) => r.s.typeDateOk).length, withTx.length, "≥ 97%"],
  ["分類正確率", withTx.filter((r) => r.s.catOk).length, withTx.length, "≥ 90%"],
  ["直接入帳的錯誤率", committed.filter((r) => r.s.wrongCommit).length, committed.length, "≤ 1%"],
  ["處理方式符合預期", rows.filter((r) => r.s.resultOk).length, rows.length, "（參考）"],
] as const;

console.log(`\n供應商：${Deno.env.get("AI_PROVIDER") ?? "anthropic"}　模型：${Deno.env.get("AI_MODEL_RECORD") ?? "mock"}　共 ${rows.length} 句\n`);
for (const [name, n, d, target] of metrics) console.log(`${name.padEnd(14, "　")} ${pct(n, d).padStart(6)}  (${n}/${d})  目標 ${target}`);
const misrecorded = rows.filter((r) => r.s.questionRecorded).length;
console.log(`${"問題被誤記成交易".padEnd(14, "　")} ${String(misrecorded).padStart(6)}  目標 0`);
const failed = rows.filter((r) => r.o.result === "failed").length;
if (failed > 0) console.log(`\n有 ${failed} 句呼叫失敗（重試後仍失敗）。`);

const bad = rows.filter((r) => !r.s.resultOk || (r.c.tx.length > 0 && !(r.s.amountOk && r.s.typeDateOk && r.s.catOk)));
if (bad.length > 0) {
  console.log(`\n不符合預期的 ${bad.length} 句：`);
  for (const { c, o, s } of bad) {
    const got = o.tx.map((t) => `${t.type} ${t.amount} ${t.occurred_on} ${t.finalCategory}`).join(" | ");
    const why = [!s.resultOk && "處理方式", !s.amountOk && "金額", s.amountOk && !s.typeDateOk && "類型/日期", s.amountOk && !s.catOk && "分類"]
      .filter(Boolean).join("、");
    console.log(`  #${c.id}「${c.input}」→ ${o.result}${got ? `：${got}` : ""}　[${c.tx.length > 0 ? why : "處理方式"}]`);
  }
}

await Deno.mkdir(new URL("results/", here), { recursive: true });
await Deno.writeTextFile(
  new URL(`results/${new Date().toISOString().replace(/[:.]/g, "-")}.json`, here),
  JSON.stringify(rows.map(({ c, o, s }) => ({ id: c.id, input: c.input, expected: c.result, got: o.result, tx: o.tx, ...s })), null, 2),
);
