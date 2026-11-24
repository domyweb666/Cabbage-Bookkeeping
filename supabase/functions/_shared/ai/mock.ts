import type { AIProvider, StructuredResult, Tool, ToolLoopResult } from "./provider.ts";
import { normalizeText } from "../rules/normalize.ts";
import { addDays, localDate } from "../utils/dates.ts";

// 沒有 AI 金鑰時用的假供應商（AI_PROVIDER=mock）：本機開發、CI、畫面測試用。
// 用很粗的關鍵字規則解析，只求流程能跑，不代表真實模型的品質。

const KEYWORDS: Array<[RegExp, string, string[], string | null]> = [
  [/netflix|spotify|youtube|icloud|訂閱|月費/i, "訂閱", ["訂閱"], "recurring"],
  [/加油|捷運|公車|計程車|uber|停車|高鐵|火車|機車|汽車|維修/i, "交通", ["交通"], null],
  [/醫生|診所|藥|掛號|醫院|牙/, "醫療", ["醫療"], null],
  [/房租|水費|電費|瓦斯|管理費|網路費/, "居住", ["居住"], "recurring"],
  [/電影|遊戲|ktv|演唱會/i, "娛樂", ["娛樂"], null],
  [/書|課程|學費|補習/, "學習", ["學習"], null],
  [/機票|住宿|飯店|旅館|旅行/, "旅行", ["旅行"], "one_off"],
  [/紅包|禮物|請客|禮金/, "人情", ["人情"], null],
  [/衣服|鞋|電腦|手機|耳機|蝦皮|momo|買/i, "購物", ["購物"], null],
  [/早餐|午餐|晚餐|宵夜|便當|飲料|咖啡|麥當勞|火鍋|吃|餐|飯|麵|奶茶/, "飲食", ["外食"], "routine"],
];

const INCOME = /薪水|薪資|獎金|收入|退款|中獎|股利|利息|入帳/;
const QUESTION = /[?？]\s*$|多少|幾筆|花最多|比.*(多|少)|哪一|什麼時候|有沒有/;

function field(user: string, name: string): string {
  const line = user.split("\n").find((l) => l.startsWith(`${name}：`));
  return line ? line.slice(name.length + 1) : "";
}

export class MockProvider implements AIProvider {
  generateStructured(req: { system: string; user: string; schema: Record<string, unknown> }): Promise<StructuredResult> {
    const raw = field(req.user, "原話");
    const timezone = field(req.user, "時區") || "Asia/Taipei";
    const at = new Date(field(req.user, "current_datetime"));
    const today = localDate(Number.isNaN(at.getTime()) ? new Date() : at, timezone);
    const usage = { model: "mock", input_tokens: req.user.length, output_tokens: 0 };

    const text = normalizeText(raw).replace(/(\d),(?=\d{3}(?:\D|$))/g, "$1");
    if (QUESTION.test(text)) {
      return Promise.resolve({ output: { intent: "query", transactions: [], hint: null }, usage });
    }

    const transactions = text
      .split(/[，,、；;。\n]/)
      .map((s) => s.trim())
      .filter(Boolean)
      .flatMap((segment) => {
        const m = segment.match(/\d+/g);
        if (!m) return [];
        const amount = Number(m[m.length - 1]);
        let date = today;
        if (/前天/.test(segment)) date = addDays(today, -2);
        else if (/昨天|昨晚/.test(segment)) date = addDays(today, -1);
        const item = segment
          .replace(/\d+/g, "")
          .replace(/今天|昨天|昨晚|前天|花了|元|塊|買了?/g, "")
          .trim() || "消費";
        const income = INCOME.test(segment);
        const hit = KEYWORDS.find(([re]) => re.test(segment));
        return [{
          type: income ? "income" : "expense",
          amount,
          occurred_on: date,
          item,
          merchant: null,
          category: income ? "收入" : hit?.[1] ?? null,
          tags: income ? ["收入"] : hit?.[2] ?? [],
          nature: income ? null : hit?.[3] ?? null,
          payment_method: null,
          missing_fields: [],
        }];
      });

    if (transactions.length === 0) {
      return Promise.resolve({
        output: { intent: "unclear", transactions: [], hint: "要記多少錢？請補上金額。" },
        usage,
      });
    }
    return Promise.resolve({ output: { intent: "record", transactions, hint: null }, usage });
  }

  async generateWithTools(req: { system: string; user: string; tools: Tool[] }): Promise<ToolLoopResult> {
    const today = field(req.user, "今天").slice(0, 10);
    const usage = { model: "mock", input_tokens: req.user.length, output_tokens: 0 };
    const tool = req.tools.find((t) => t.name === "sum_transactions");
    if (!tool) return { text: "", calls: [], usage };

    const input = { filters: { date_from: `${today.slice(0, 7)}-01`, date_to: today, type: "expense" } };
    const result = await tool.run(input) as { total: number; count: number };
    const text = result.count === 0
      ? "這個月還沒有支出紀錄。"
      : `這個月到目前支出共 NT$${result.total.toLocaleString("en-US")}，一共 ${result.count} 筆。`;
    return { text, calls: [{ name: tool.name, input, result, is_error: false }], usage };
  }
}
