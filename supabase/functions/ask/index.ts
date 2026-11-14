import { runAsk } from "../_shared/ask.ts";
import { AppError } from "../_shared/types.ts";
import { serve } from "../_shared/utils/http.ts";

// POST /functions/v1/ask  { "question": "這個月外食花多少？" }
serve((body, ctx) => {
  const question = (body as { question?: unknown } | null)?.question;
  if (typeof question !== "string") throw new AppError(400, "invalid_input", "請輸入想問的問題。");
  return runAsk(question, ctx);
});
