// 規格 9.4：資料庫測試。需要本機 Supabase。
import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { anon, categories, dbTest, newUser, seed } from "./helpers.ts";

dbTest("RLS：使用者看不到也改不了別人的資料", async () => {
  const a = await newUser();
  const b = await newUser();
  const [tx] = await seed(a, [{ amount: 100, occurred_on: "2026-11-10", item: "午餐", category: "飲食" }]);

  const seen = await b.db.from("transactions").select("id");
  assertEquals(seen.data, []);

  const updated = await b.db.from("transactions").update({ amount: 1 }).eq("id", tx.id).select("id");
  assertEquals(updated.data, []);

  // 不能把資料寫到別人名下。
  const cats = await categories(b.db);
  const forged = await b.db.from("transactions").insert({
    user_id: a.id, type: "expense", amount: 5, occurred_on: "2026-11-10", item: "x",
    category_id: cats["飲食"].id, category_source: "ai",
  });
  assertNotEquals(forged.error, null);

  const mine = await a.db.from("transactions").select("amount").eq("id", tx.id).single();
  assertEquals(mine.data?.amount, 100);

  assertEquals((await b.db.from("entries").select("id")).data, []);
  assertEquals((await b.db.from("profiles").select("id")).data?.map((p) => p.id), [b.id]);
});

dbTest("未登入（anon）讀不到任何資料", async () => {
  const a = await newUser();
  await seed(a, [{ amount: 100, occurred_on: "2026-11-10", item: "午餐", category: "飲食" }]);
  const res = await anon().from("transactions").select("id");
  assertEquals(res.data ?? [], []);
});

dbTest("註冊時自動建立 profile，預設 TWD、台北時區、直接入帳開啟", async () => {
  const a = await newUser();
  const { data } = await a.db.from("profiles").select("currency, timezone, auto_commit").single();
  assertEquals(data, { currency: "TWD", timezone: "Asia/Taipei", auto_commit: true });

  // 只能改直接入帳的開關與門檻。
  assertEquals((await a.db.from("profiles").update({ auto_commit: false, auto_commit_max: 3000 }).eq("id", a.id)).error, null);
  assertNotEquals((await a.db.from("profiles").update({ auto_commit_max: 0 }).eq("id", a.id)).error, null);
  assertNotEquals((await a.db.from("profiles").update({ currency: "USD" }).eq("id", a.id)).error, null);
});

dbTest("金額不得小於等於 0", async () => {
  const a = await newUser();
  const cats = await categories(a.db);
  for (const amount of [0, -100]) {
    const res = await a.db.from("transactions").insert({
      user_id: a.id, type: "expense", amount, occurred_on: "2026-11-10", item: "x",
      category_id: cats["飲食"].id, category_source: "ai",
    });
    assertNotEquals(res.error, null);
  }
});

dbTest("軟刪除不計入統計，復原後恢復計入", async () => {
  const a = await newUser();
  const [t1] = await seed(a, [
    { amount: 300, occurred_on: "2026-11-10", item: "晚餐", category: "飲食" },
    { amount: 200, occurred_on: "2026-11-11", item: "加油", category: "交通" },
  ]);
  const overview = async () => (await a.db.rpc("monthly_overview", { month: "2026-11-01" })).data;
  const sum = async () => (await a.db.rpc("q_sum", { filters: {} })).data;

  assertEquals((await overview()).total_expense, 500);
  assertEquals((await sum()).total, 500);

  await a.db.from("transactions").update({ deleted_at: new Date().toISOString() }).eq("id", t1.id);
  assertEquals((await overview()).total_expense, 200);
  assertEquals((await overview()).by_category.map((c: { name: string }) => c.name), ["交通"]);
  assertEquals((await sum()).count, 1);

  await a.db.from("transactions").update({ deleted_at: null }).eq("id", t1.id);
  assertEquals((await overview()).total_expense, 500);
  assertEquals((await sum()).count, 2);
});

dbTest("本月概覽：收入、分類長條、扣掉一次性支出", async () => {
  const a = await newUser();
  await seed(a, [
    { amount: 100, occurred_on: "2026-11-01", item: "早餐", category: "飲食", nature: "routine" },
    { amount: 250, occurred_on: "2026-11-30", item: "晚餐", category: "飲食" },
    { amount: 4650, occurred_on: "2026-11-12", item: "機車維修", category: "交通", nature: "one_off" },
    { type: "income", amount: 52000, occurred_on: "2026-11-05", item: "薪水", category: "收入" },
    { amount: 999, occurred_on: "2026-10-31", item: "上個月", category: "飲食" },
    { amount: 888, occurred_on: "2026-12-01", item: "下個月", category: "飲食" },
  ]);
  const { data } = await a.db.rpc("monthly_overview", { month: "2026-11-15" });
  assertEquals(data.month, "2026-11");
  assertEquals(data.total_expense, 5000);
  assertEquals(data.total_income, 52000);
  assertEquals(data.routine_expense, 350);
  assertEquals(data.one_off_expense, 4650);
  assertEquals(
    data.by_category.map((c: { name: string; total: number; count: number }) => [c.name, c.total, c.count]),
    [["交通", 4650, 1], ["飲食", 350, 2]],
  );
});

dbTest("使用者不能硬刪除交易，只能軟刪除", async () => {
  const a = await newUser();
  const [tx] = await seed(a, [{ amount: 100, occurred_on: "2026-11-10", item: "午餐", category: "飲食" }]);
  await a.db.from("transactions").delete().eq("id", tx.id);
  assertEquals((await a.db.from("transactions").select("id")).data?.length, 1);
});

dbTest("手動改分類會學成規則；category_source = user 不會被自動流程覆寫", async () => {
  const a = await newUser();
  const cats = await categories(a.db);
  const [tx] = await seed(a, [
    { amount: 188, occurred_on: "2026-11-10", item: "大麥克套餐", merchant: "麥當勞", category: "飲食" },
  ]);

  await a.db.from("transactions").update({ category_id: cats["娛樂"].id, category_source: "user" }).eq("id", tx.id);
  const rules = await a.db.from("user_rules").select("match_text, category_id");
  assertEquals(rules.data, [{ match_text: "麥當勞", category_id: cats["娛樂"].id }]);

  // 自動流程（ai / rule）想改掉使用者指定的分類：被擋下。
  const overwrite = await a.db.from("transactions")
    .update({ category_id: cats["飲食"].id, category_source: "ai" }).eq("id", tx.id);
  assertNotEquals(overwrite.error, null);

  // 改別的欄位時，來源仍維持 user。
  await a.db.from("transactions").update({ note: "聚餐", category_source: "ai" }).eq("id", tx.id);
  const after = await a.db.from("transactions").select("category_id, category_source, note").eq("id", tx.id).single();
  assertEquals(after.data, { category_id: cats["娛樂"].id, category_source: "user", note: "聚餐" });

  // 使用者自己再改一次：規則跟著更新，不會多一條。
  await a.db.from("transactions").update({ category_id: cats["人情"].id, category_source: "user" }).eq("id", tx.id);
  const again = await a.db.from("user_rules").select("match_text, category_id");
  assertEquals(again.data, [{ match_text: "麥當勞", category_id: cats["人情"].id }]);
});

dbTest("原話不可修改", async () => {
  const a = await newUser();
  const id = crypto.randomUUID();
  await a.db.from("entries").insert({
    id, user_id: a.id, raw_text: "麥當勞 188", source: "text", client_created_at: "2026-11-15T04:30:00Z",
  });
  assertNotEquals((await a.db.from("entries").update({ raw_text: "麥當勞 1" }).eq("id", id)).error, null);
  assertEquals((await a.db.from("entries").update({ status: "failed" }).eq("id", id)).error, null);
  assertEquals((await a.db.from("entries").select("raw_text").eq("id", id).single()).data?.raw_text, "麥當勞 188");
});

dbTest("用量紀錄：使用者只能讀，不能自己新增或刪除", async () => {
  const a = await newUser();
  const ins = await a.db.from("ai_usage").insert({ user_id: a.id, feature: "record", model: "x" });
  assertNotEquals(ins.error, null);
});

dbTest("刪除所有資料只刪自己的", async () => {
  const a = await newUser();
  const b = await newUser();
  await seed(a, [{ amount: 100, occurred_on: "2026-11-10", item: "午餐", category: "飲食" }]);
  await seed(b, [{ amount: 200, occurred_on: "2026-11-10", item: "晚餐", category: "飲食" }]);
  assertEquals((await a.db.rpc("delete_all_my_data")).error, null);
  assertEquals((await a.db.from("transactions").select("id")).data, []);
  assertEquals((await b.db.from("transactions").select("id")).data?.length, 1);
  assertEquals((await a.db.from("categories").select("id")).data?.length, 12);
});
