// 統一的 AI 供應商介面（規格 6.1）。供應商與模型名稱都放環境變數，前端不能指定。

export interface Usage {
  model: string;
  input_tokens: number;
  output_tokens: number;
}

export interface Tool {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
  /** 由後端執行；丟出例外時會把錯誤訊息回給模型。 */
  run: (input: unknown) => Promise<unknown>;
}

export interface ToolCall {
  name: string;
  input: unknown;
  result: unknown;
  is_error: boolean;
}

export interface StructuredResult {
  output: unknown;
  usage: Usage;
}

export interface ToolLoopResult {
  text: string;
  calls: ToolCall[];
  usage: Usage;
}

export interface AIProvider {
  generateStructured(req: {
    system: string;
    user: string;
    schema: Record<string, unknown>;
  }): Promise<StructuredResult>;

  generateWithTools(req: {
    system: string;
    user: string;
    tools: Tool[];
  }): Promise<ToolLoopResult>;
}

/** AI 呼叫失敗。retryable 為 false 時（例如被拒絕、金鑰錯誤）不重試。 */
export class AIError extends Error {
  constructor(message: string, public retryable: boolean) {
    super(message);
  }
}
