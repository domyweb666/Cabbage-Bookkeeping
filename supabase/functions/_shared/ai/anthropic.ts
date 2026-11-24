import Anthropic from "npm:@anthropic-ai/sdk@1.8.0";
import { AIError, type AIProvider, type StructuredResult, type Tool, type ToolCall, type ToolLoopResult } from "./provider.ts";

const MAX_TOOL_ROUNDS = 6;

export interface AnthropicOptions {
  apiKey: string;
  modelRecord: string;
  modelAsk: string;
}

/**
 * Claude 供應商。
 * - 記帳解析：結構化輸出（output_config.format），一次呼叫。
 * - 查帳：工具迴圈，模型只能呼叫後端提供的查詢工具。
 * effort 設 low：兩件事都是短任務，要的是快（規格要求文字入帳 8 秒內）。
 */
export class AnthropicProvider implements AIProvider {
  private client: Anthropic;

  constructor(private opts: AnthropicOptions) {
    // 重試由呼叫端統一做一次（規格 6.1），SDK 自己不再重試。
    this.client = new Anthropic({ apiKey: opts.apiKey, maxRetries: 0, timeout: 25_000 });
  }

  async generateStructured(req: {
    system: string;
    user: string;
    schema: Record<string, unknown>;
  }): Promise<StructuredResult> {
    const model = this.opts.modelRecord;
    const response = await this.call(() =>
      this.client.messages.create({
        model,
        max_tokens: 16000,
        system: req.system,
        messages: [{ role: "user", content: req.user }],
        output_config: {
          effort: "low",
          format: { type: "json_schema", schema: req.schema },
        },
      })
    );

    if (response.stop_reason === "refusal") throw new AIError("模型拒絕處理這段輸入", false);
    if (response.stop_reason === "max_tokens") throw new AIError("輸出被截斷", true);

    const text = response.content
      .filter((b): b is Anthropic.TextBlock => b.type === "text")
      .map((b) => b.text)
      .join("");
    let output: unknown;
    try {
      output = JSON.parse(text);
    } catch {
      throw new AIError("模型輸出不是合法 JSON", true);
    }
    return {
      output,
      usage: {
        model,
        input_tokens: response.usage.input_tokens,
        output_tokens: response.usage.output_tokens,
      },
    };
  }

  async generateWithTools(req: { system: string; user: string; tools: Tool[] }): Promise<ToolLoopResult> {
    const model = this.opts.modelAsk;
    const tools: Anthropic.Tool[] = req.tools.map((t) => ({
      name: t.name,
      description: t.description,
      input_schema: t.input_schema as Anthropic.Tool.InputSchema,
    }));
    const messages: Anthropic.MessageParam[] = [{ role: "user", content: req.user }];
    const calls: ToolCall[] = [];
    let inputTokens = 0;
    let outputTokens = 0;
    let text = "";

    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      const response = await this.call(() =>
        this.client.messages.create({
          model,
          max_tokens: 16000,
          system: req.system,
          tools,
          messages,
          output_config: { effort: "low" },
        })
      );
      inputTokens += response.usage.input_tokens;
      outputTokens += response.usage.output_tokens;

      if (response.stop_reason === "refusal") throw new AIError("模型拒絕處理這個問題", false);
      if (response.stop_reason === "max_tokens") throw new AIError("輸出被截斷", true);

      text = response.content
        .filter((b): b is Anthropic.TextBlock => b.type === "text")
        .map((b) => b.text)
        .join("")
        .trim();

      const toolUses = response.content.filter(
        (b): b is Anthropic.ToolUseBlock => b.type === "tool_use",
      );
      if (response.stop_reason !== "tool_use" || toolUses.length === 0) break;

      messages.push({ role: "assistant", content: response.content });

      // 同一輪的工具呼叫一起執行，結果放在同一則 user 訊息裡回傳。
      const results = await Promise.all(toolUses.map(async (use): Promise<Anthropic.ToolResultBlockParam> => {
        const tool = req.tools.find((t) => t.name === use.name);
        try {
          if (!tool) throw new Error(`沒有這個工具：${use.name}`);
          const result = await tool.run(use.input);
          calls.push({ name: use.name, input: use.input, result, is_error: false });
          return { type: "tool_result", tool_use_id: use.id, content: JSON.stringify(result) };
        } catch (err) {
          const message = err instanceof Error ? err.message : "工具執行失敗";
          calls.push({ name: use.name, input: use.input, result: message, is_error: true });
          return { type: "tool_result", tool_use_id: use.id, content: message, is_error: true };
        }
      }));
      messages.push({ role: "user", content: results });
    }

    return { text, calls, usage: { model, input_tokens: inputTokens, output_tokens: outputTokens } };
  }

  /** 把 SDK 的例外轉成 AIError，分清楚能不能重試。 */
  private async call<T>(fn: () => Promise<T>): Promise<T> {
    try {
      return await fn();
    } catch (err) {
      if (err instanceof Anthropic.BadRequestError) throw new AIError("AI 請求格式錯誤", false);
      if (err instanceof Anthropic.AuthenticationError) throw new AIError("AI 金鑰無效", false);
      if (err instanceof Anthropic.PermissionDeniedError) throw new AIError("AI 金鑰沒有權限", false);
      if (err instanceof Anthropic.NotFoundError) throw new AIError("找不到指定的模型", false);
      if (err instanceof Anthropic.RateLimitError) throw new AIError("AI 服務忙碌中", true);
      if (err instanceof Anthropic.APIError) throw new AIError(`AI 服務錯誤 ${err.status ?? ""}`, true);
      throw new AIError("無法連上 AI 服務", true);
    }
  }
}
