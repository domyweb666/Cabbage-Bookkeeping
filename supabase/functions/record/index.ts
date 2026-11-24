import { handleConfirm, handleRecord } from "../_shared/record.ts";
import { serve } from "../_shared/utils/http.ts";

// POST /functions/v1/record          記一句話
// POST /functions/v1/record/confirm  送出修正後的草稿
serve((body, ctx, req) => {
  const path = new URL(req.url).pathname.replace(/\/+$/, "");
  return path.endsWith("/confirm") ? handleConfirm(body, ctx) : handleRecord(body, ctx);
});
