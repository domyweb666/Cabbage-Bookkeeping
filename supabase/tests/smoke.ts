// 端到端冒煙測試：真的透過 HTTP 打本機的 Edge Function（AI_PROVIDER=mock）。
// 用法：deno run -A supabase/tests/smoke.ts
import { createClient } from "npm:@supabase/supabase-js@2.119.0";

const url = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("API_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("ANON_KEY");
if (!url || !anonKey) throw new Error("需要 SUPABASE_URL 與 SUPABASE_ANON_KEY");

const supabase = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
const { data: auth, error } = await supabase.auth.signInAnonymously();
if (error || !auth.session) throw new Error(`匿名登入失敗：${error?.message}`);

async function post(path: string, body: unknown, token: string | null = auth.session!.access_token) {
  const res = await fetch(`${url}/functions/v1/${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: anonKey!,
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: res.status, json: await res.json() };
}

function check(name: string, ok: boolean, detail: unknown) {
  if (!ok) {
    console.error(`✗ ${name}`, JSON.stringify(detail));
    Deno.exit(1);
  }
  console.log(`✓ ${name}`);
}

const now = new Date().toISOString();
const entry = { entry_id: crypto.randomUUID(), raw_text: "麥當勞 188，飲料 55", source: "text", client_created_at: now };

const first = await post("record", entry);
check("record：兩筆直接入帳", first.status === 200 && first.json.success === true &&
  first.json.data.result === "committed" && first.json.data.transactions.length === 2 &&
  typeof first.json.request_id === "string", first);

const again = await post("record", entry);
check("record：同一個 entry_id 重送不重複寫入",
  again.json.data.transactions.map((t: { id: string }) => t.id).join() ===
    first.json.data.transactions.map((t: { id: string }) => t.id).join(), again);

const big = { ...entry, entry_id: crypto.randomUUID(), raw_text: "買電腦 45000" };
const draft = await post("record", big);
check("record：超過門檻回傳草稿", draft.json.data.result === "needs_confirm", draft);

const confirmed = await post("record/confirm", { entry_id: big.entry_id, transactions: draft.json.data.drafts });
check("record/confirm：確認後寫入", confirmed.json.data.result === "committed", confirmed);

const asked = await post("ask", { question: "這個月花多少？" });
check("ask：數字來自資料庫", asked.status === 200 && asked.json.data.evidence[0].total === 45243 &&
  asked.json.data.answer.includes("NT$45,243"), asked);

const viaRecord = await post("record", { ...entry, entry_id: crypto.randomUUID(), raw_text: "這個月花多少？" });
check("record：問句轉給查帳", viaRecord.json.data.result === "answer", viaRecord);

const noAuth = await post("record", entry, null);
check("沒帶 JWT 會被擋下", noAuth.status === 401, noAuth);

const tooLong = await post("record", { ...entry, entry_id: crypto.randomUUID(), raw_text: "午".repeat(501) });
check("超過 500 字回傳中文錯誤訊息", tooLong.status === 400 && tooLong.json.success === false &&
  tooLong.json.error.code === "too_long", tooLong);

console.log("冒煙測試全部通過");
