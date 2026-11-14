// 規格 9.3：查帳測試。固定種子資料，每個工具的結果都要等於手算值。
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { Tool } from "../functions/_shared/ai/provider.ts";
import { runAsk } from "../functions/_shared/ask.ts";
import { buildTools } from "../functions/_shared/query/tools.ts";
import { AppError } from "../functions/_shared/types.ts";
import { ctxFor, dbTest, newUser, ScriptedAI, seed, type SeedTx, type TestUser } from "./helpers.ts";

// 手算：
// 11 月支出 = 188 + 120 + 450 + 500 + 4650 + 390 + 1280 = 7578（7 筆）
// 10 月支出 = 300 + 600 = 900（2 筆）
// 11 月外食（tag）= 188 + 120 + 450 = 758（3 筆）
// 11 月飲食（分類）= 758；交通 = 500 + 4650 = 5150；訂閱 390；購物 1280
const SEED: SeedTx[] = [
  { amount: 188, occurred_on: "2026-11-15", item: "大麥克套餐", merchant: "麥當勞", category: "飲食", tags: ["外食", "速食"], nature: "routine" },
  { amount: 120, occurred_on: "2026-11-14", item: "便當", category: "飲食", tags: ["外食"], nature: "routine" },
  { amount: 450, occurred_on: "2026-11-14", item: "火鍋", merchant: "鼎王", category: "飲食", tags: ["外食", "聚餐"], note: "跟同事" },
  { amount: 500, occurred_on: "2026-11-10", item: "加油", merchant: "中油", category: "交通", tags: ["機車"], nature: "routine" },
  { amount: 4650, occurred_on: "2026-11-08", item: "機車維修", category: "交通", tags: ["機車"], nature: "one_off" },
  { amount: 390, occurred_on: "2026-11-05", item: "Netflix", merchant: "Netflix", category: "訂閱", tags: ["訂閱"], nature: "recurring" },
  { amount: 1280, occurred_on: "2026-11-02", item: "衣服", merchant: "UNIQLO", category: "購物", tags: ["服飾"] },
  { type: "income", amount: 52000, occurred_on: "2026-11-05", item: "薪水", category: "收入" },
  { amount: 300, occurred_on: "2026-10-20", item: "拉麵", category: "飲食", tags: ["外食"] },
  { amount: 600, occurred_on: "2026-10-12", item: "加油", merchant: "中油", category: "交通", tags: ["機車"] },
];

const NOV = { date_from: "2026-11-01", date_to: "2026-11-30" };
const OCT = { date_from: "2026-10-01", date_to: "2026-10-31" };

async function seeded(): Promise<{ user: TestUser; tool: (name: string, input: unknown) => Promise<any> }> {
  const user = await newUser();
  await seed(user, SEED);
  const tools = buildTools(user.db);
  return { user, tool: (name, input) => tools.find((t) => t.name === name)!.run(input) };
}

dbTest("sum_transactions：各種篩選條件等於手算值", async () => {
  const { tool } = await seeded();
  const sum = (filters: unknown) => tool("sum_transactions", { filters });

  assertEquals(await sum({ ...NOV, type: "expense" }), { total: 7578, count: 7 });
  assertEquals(await sum({ ...NOV, tags: ["外食"] }), { total: 758, count: 3 });
  assertEquals(await sum({ ...NOV, categories: ["交通"] }), { total: 5150, count: 2 });
  assertEquals(await sum({ ...NOV, categories: ["交通", "訂閱"] }), { total: 5540, count: 3 });
  assertEquals(await sum({ ...NOV, nature: "one_off" }), { total: 4650, count: 1 });
  assertEquals(await sum({ ...NOV, type: "income" }), { total: 52000, count: 1 });
  assertEquals(await sum({ merchant_contains: "中油" }), { total: 1100, count: 2 });
  assertEquals(await sum({ type: "expense", amount_min: 450, amount_max: 1280 }), { total: 2830, count: 4 });
  assertEquals(await sum({ text_contains: "同事" }), { total: 450, count: 1 });
  assertEquals(await sum({ ...NOV, tags: ["寵物"] }), { total: 0, count: 0 });
  // 萬用字元當一般文字處理。
  assertEquals(await sum({ text_contains: "%" }), { total: 0, count: 0 });
});

dbTest("text_contains 也會搜尋原話", async () => {
  const user = await newUser();
  const entryId = crypto.randomUUID();
  await user.db.from("entries").insert({
    id: entryId, user_id: user.id, raw_text: "跟阿明吃宵夜 320", source: "text", client_created_at: "2026-11-15T04:30:00Z",
  });
  const [tx] = await seed(user, [{ amount: 320, occurred_on: "2026-11-15", item: "宵夜", category: "飲食" }]);
  await user.db.from("transactions").update({ entry_id: entryId }).eq("id", tx.id);
  const result = await buildTools(user.db)[0].run({ filters: { text_contains: "阿明" } });
  assertEquals(result, { total: 320, count: 1 });
});

dbTest("group_transactions：依分類、標籤、月份、性質分組", async () => {
  const { tool } = await seeded();
  const group = async (filters: unknown, group_by: string) => {
    const r = await tool("group_transactions", { filters, group_by });
    return r.groups.map((g: { key: string; total: number; count: number }) => [g.key, g.total, g.count]);
  };

  assertEquals(await group({ ...NOV, type: "expense" }, "category"),
    [["交通", 5150, 2], ["購物", 1280, 1], ["飲食", 758, 3], ["訂閱", 390, 1]]);
  assertEquals(await group({ ...NOV, categories: ["飲食"] }, "tag"),
    [["外食", 758, 3], ["聚餐", 450, 1], ["速食", 188, 1]]);
  assertEquals(await group({ type: "expense" }, "month"), [["2026-10", 900, 2], ["2026-11", 7578, 7]]);
  assertEquals(await group({ ...NOV, type: "expense", date_from: "2026-11-14" }, "day"),
    [["2026-11-14", 570, 2], ["2026-11-15", 188, 1]]);
  assertEquals(await group({ ...NOV, categories: ["交通"] }, "nature"), [["one_off", 4650, 1], ["routine", 500, 1]]);
  assertEquals(await group({ ...NOV, categories: ["交通"] }, "merchant"), [["（未填商家）", 4650, 1], ["中油", 500, 1]]);
});

dbTest("list_transactions：排序與筆數上限", async () => {
  const { tool, user } = await seeded();
  const top = await tool("list_transactions", { filters: { ...NOV, type: "expense" }, order: "amount_desc", limit: 3 });
  assertEquals(top.transactions.map((t: { item: string; amount: number }) => [t.item, t.amount]),
    [["機車維修", 4650], ["衣服", 1280], ["加油", 500]]);
  assertEquals(top.transactions[0].category, "交通");

  const latest = await tool("list_transactions", { filters: { type: "expense" } });
  assertEquals(latest.transactions[0].occurred_on, "2026-11-15");
  assertEquals(latest.count, 9);

  // 上限 20：就算模型要 500 筆也只給 20。
  await seed(user, Array.from({ length: 25 }, (_, i) => ({
    amount: 10 + i, occurred_on: "2026-09-01", item: `零食${i}`, category: "飲食",
  })));
  const capped = await tool("list_transactions", { filters: {}, limit: 500 });
  assertEquals(capped.transactions.length, 20);
});

dbTest("compare_periods：兩段期間的總額與差額", async () => {
  const { tool } = await seeded();
  const r = await tool("compare_periods", { filters: { type: "expense" }, period_a: NOV, period_b: OCT });
  assertEquals([r.period_a.total, r.period_a.count], [7578, 7]);
  assertEquals([r.period_b.total, r.period_b.count], [900, 2]);
  assertEquals([r.difference, r.abs_difference], [6678, 6678]);

  const reversed = await tool("compare_periods", { filters: { categories: ["交通"] }, period_a: OCT, period_b: NOV });
  assertEquals([reversed.difference, reversed.abs_difference], [-4550, 4550]);
});

dbTest("工具參數不合法時拒絕執行", async () => {
  const { tool } = await seeded();
  await assertRejects(() => tool("sum_transactions", { filters: { date_from: "上個月" } }));
  await assertRejects(() => tool("group_transactions", { filters: {}, group_by: "user_id" }));
  await assertRejects(() => tool("compare_periods", { filters: {}, period_a: NOV }));
});

/** 模型呼叫 sum_transactions 之後照 say() 的內容回答。 */
function asker(filters: unknown, say: (r: { total: number; count: number }) => string) {
  return new ScriptedAI(() => ({}), async (tools: Tool[]) => {
    const input = { filters };
    const result = await tools.find((t) => t.name === "sum_transactions")!.run(input) as { total: number; count: number };
    return { text: say(result), calls: [{ name: "sum_transactions", input, result, is_error: false }] };
  });
}

dbTest("回答的數字來自工具結果，並附上依據", async () => {
  const { user } = await seeded();
  const ai = asker({ ...NOV, tags: ["外食"] }, (r) => `11 月到目前外食共 NT$${r.total}，一共 ${r.count} 筆。`);
  const res = await runAsk("這個月外食花多少？", ctxFor(user, ai));
  assertEquals(res.answer, "11 月到目前外食共 NT$758，一共 3 筆。");
  assertEquals(res.evidence.length, 1);
  assertEquals([res.evidence[0].tool, res.evidence[0].count, res.evidence[0].total], ["sum_transactions", 3, 758]);
  assertEquals(res.evidence[0].filters, { ...NOV, tags: ["外食"] });
  assertEquals(res.evidence[0].transaction_ids.length, 3);

  const usage = await user.db.from("ai_usage").select("feature, model");
  assertEquals(usage.data, [{ feature: "ask", model: "scripted" }]);
});

dbTest("模型講出工具結果裡沒有的金額：改回傳制式摘要", async () => {
  const { user } = await seeded();
  const ai = asker({ ...NOV, tags: ["外食"] }, () => "外食大約 NT$800，平均每天 53 元。");
  const res = await runAsk("這個月外食花多少？", ctxFor(user, ai));
  assertEquals(res.answer, "共 NT$758，一共 3 筆。");
});

dbTest("查無資料時不編造", async () => {
  const { user } = await seeded();
  const made = asker({ ...NOV, tags: ["寵物"] }, () => "寵物大概花了 NT$1,200。");
  assertEquals((await runAsk("寵物花多少？", ctxFor(user, made))).answer, "查不到符合條件的紀錄。");

  const honest = asker({ ...NOV, tags: ["寵物"] }, () => "這個月查不到寵物相關的紀錄。");
  const res = await runAsk("寵物花多少？", ctxFor(user, honest));
  assertEquals(res.answer, "這個月查不到寵物相關的紀錄。");
  assertEquals([res.evidence[0].count, res.evidence[0].total], [0, 0]);
});

dbTest("A 使用者問不到 B 使用者的資料", async () => {
  await seeded();
  const b = await newUser();
  const ai = asker({ user_id: "anyone", date_from: "2000-01-01" }, (r) => `共 NT$${r.total}，${r.count} 筆。`);
  const res = await runAsk("大家總共花多少？", ctxFor(b, ai));
  assertEquals(res.answer, "共 NT$0，0 筆。");
  assertEquals(res.evidence[0].transaction_ids, []);
});

dbTest("提問的每日上限", async () => {
  const { user } = await seeded();
  const ctx = ctxFor(user, asker({}, (r) => `共 NT$${r.total}。`), { dailyLimitAsk: 1 });
  ctx.now = () => new Date();
  await runAsk("總共花多少？", ctx);
  const err = await assertRejects(() => runAsk("總共花多少？", ctx), AppError);
  assertEquals(err.code, "daily_limit");
});
