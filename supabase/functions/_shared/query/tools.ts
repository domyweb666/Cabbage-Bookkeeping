import type { SupabaseClient } from "npm:@supabase/supabase-js@2.119.0";
import type { Tool } from "../ai/provider.ts";
import { FilterError, FILTERS_SCHEMA, parseFilters, parsePeriod } from "./filters.ts";

// 查帳的四個工具（規格 6.4）。模型只能呼叫這四個；數字全部由資料庫算。
// db 是帶著使用者 JWT 的連線，資料庫函式用 auth.uid() 與 RLS 限定只查本人。

const GROUPS = ["category", "tag", "merchant", "nature", "day", "month"] as const;
const SORTS = ["date_desc", "date_asc", "amount_desc", "amount_asc"] as const;

const PERIOD_SCHEMA = {
  type: "object",
  properties: {
    date_from: { type: "string", description: "YYYY-MM-DD" },
    date_to: { type: "string", description: "YYYY-MM-DD" },
  },
  required: ["date_from", "date_to"],
};

function obj(input: unknown): Record<string, unknown> {
  if (typeof input !== "object" || input === null) throw new FilterError("參數必須是物件");
  return input as Record<string, unknown>;
}

async function rpc(db: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error("查詢失敗");
  return data;
}

export function buildTools(db: SupabaseClient): Tool[] {
  return [
    {
      name: "sum_transactions",
      description: "回傳符合條件的交易總額（total）與筆數（count）。問「花多少」「總共多少」時用。",
      input_schema: { type: "object", properties: { filters: FILTERS_SCHEMA }, required: ["filters"] },
      run: async (input) => {
        const filters = parseFilters(obj(input).filters);
        const data = await rpc(db, "q_sum", { filters }) as Record<string, unknown>;
        return { total: Number(data.total), count: Number(data.count) };
      },
    },
    {
      name: "group_transactions",
      description:
        "依 category、tag、merchant、nature、day、month 分組加總，回傳每組的 total 與 count。問「花在哪」「哪一類最多」「每天/每月」時用。",
      input_schema: {
        type: "object",
        properties: { filters: FILTERS_SCHEMA, group_by: { type: "string", enum: [...GROUPS] } },
        required: ["filters", "group_by"],
      },
      run: async (input) => {
        const o = obj(input);
        const filters = parseFilters(o.filters);
        if (!GROUPS.includes(o.group_by as typeof GROUPS[number])) throw new FilterError("group_by 不支援");
        return await rpc(db, "q_group", { filters, group_by: o.group_by });
      },
    },
    {
      name: "list_transactions",
      description: "列出符合條件的交易明細，最多 20 筆。問「最貴的是哪筆」「買了什麼」時用。",
      input_schema: {
        type: "object",
        properties: {
          filters: FILTERS_SCHEMA,
          order: { type: "string", enum: [...SORTS], description: "預設 date_desc" },
          limit: { type: "integer", description: "1 到 20，預設 20" },
        },
        required: ["filters"],
      },
      run: async (input) => {
        const o = obj(input);
        const filters = parseFilters(o.filters);
        const sort = SORTS.includes(o.order as typeof SORTS[number]) ? o.order : "date_desc";
        const limit = typeof o.limit === "number" && Number.isInteger(o.limit)
          ? Math.min(Math.max(o.limit, 1), 20)
          : 20;
        return await rpc(db, "q_list", { filters, sort, max_rows: limit });
      },
    },
    {
      name: "compare_periods",
      description:
        "比較兩段期間的總額。回傳兩段各自的 total 與 count，以及 difference（period_a 減 period_b）與 abs_difference。需要「比上個月多多少」時用，不要自己相減。",
      input_schema: {
        type: "object",
        properties: {
          filters: { ...FILTERS_SCHEMA, description: "共同的篩選條件；日期請放在 period_a 與 period_b" },
          period_a: PERIOD_SCHEMA,
          period_b: PERIOD_SCHEMA,
        },
        required: ["filters", "period_a", "period_b"],
      },
      run: async (input) => {
        const o = obj(input);
        const filters = parseFilters(o.filters);
        delete filters.date_from;
        delete filters.date_to;
        const period_a = parsePeriod(o.period_a, "period_a");
        const period_b = parsePeriod(o.period_b, "period_b");
        return await rpc(db, "q_compare", { filters, period_a, period_b });
      },
    },
  ];
}
