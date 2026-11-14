// 金額比對前的正規化：全形轉半形、去千分位。
// 「元」「塊」不需要另外移除，因為只取數字串。

/** 全形英數與符號轉半形，全形空白轉半形空白。 */
export function normalizeText(raw: string): string {
  let out = "";
  for (const ch of raw) {
    const code = ch.codePointAt(0)!;
    if (code >= 0xff01 && code <= 0xff5e) out += String.fromCodePoint(code - 0xfee0);
    else if (code === 0x3000) out += " ";
    else out += ch;
  }
  return out;
}

/**
 * 取出原話裡所有阿拉伯數字的整數。
 * 帶小數的數字不算（金額只收整數）；中文數字（三百、兩千、3萬）不解析，
 * 所以 AI 若把「3萬」解成 30000 會對不上，交給使用者確認。
 */
export function extractNumbers(raw: string): number[] {
  const text = normalizeText(raw).replace(/(\d),(?=\d{3}(?:\D|$))/g, "$1");
  const found = text.match(/\d+(?:\.\d+)?/g) ?? [];
  return found
    .filter((s) => !s.includes("."))
    .map((s) => Number(s))
    .filter((n) => Number.isSafeInteger(n));
}

/**
 * 每筆金額是否都能在原話中找到對應數字。
 * 一個數字只能對應一筆：「早餐午餐各 80」解成兩筆 80 時，第二筆對不上。
 */
export function matchAmounts(amounts: number[], raw: string): boolean[] {
  const pool = extractNumbers(raw);
  return amounts.map((amount) => {
    const i = pool.indexOf(amount);
    if (i === -1) return false;
    pool.splice(i, 1);
    return true;
  });
}
