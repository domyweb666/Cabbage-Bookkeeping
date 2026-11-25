// App Store Connect API 的共用小工具：讀環境變數、簽 JWT、打 API。零套件，只用 node 內建的。
// 環境變數：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8_PATH
// repo 公開，所以錯誤只印 Apple 回的代碼與說明，不印 JWT 和整包回應。
import { createPrivateKey, sign } from "node:crypto";
import { readFileSync } from "node:fs";

export const BUNDLE_ID = "org.domyweb.baicai";
export const APP_GROUP = "group.org.domyweb.baicai";
// 要簽章的兩個 target。描述檔名跟 project.yml 的 PROVISIONING_PROFILE_SPECIFIER、ExportOptions.plist 要一字不差
export const TARGETS = [
  { bundleId: BUNDLE_ID, profileName: "Baicai CI App Store" },
  { bundleId: `${BUNDLE_ID}.widget`, profileName: "Baicai Widget CI App Store" },
];

const API = "https://api.appstoreconnect.apple.com";
const base64url = (input) => Buffer.from(input).toString("base64url");

/// 一次把缺的環境變數列完
export function requireEnv(...names) {
  const missing = names.filter((name) => !process.env[name]);
  if (missing.length > 0) throw new Error(`缺環境變數：${missing.join("、")}`);
  return names.map((name) => process.env[name]);
}

/// 把錯誤翻成看得懂的一行，並讓這一步變紅
export function reportFailure(error) {
  let hint = "";
  if (error.status === 401) {
    hint = "Apple 不認這把金鑰：Key ID、Issuer ID、.p8 三個不是同一組，或金鑰被撤銷了。";
  } else if (error.status === 403) {
    hint = "金鑰權限不夠（要 App 管理 App Manager 以上，而且能動描述檔），或帳號有合約沒同意。";
  }
  console.error(`::error::${hint}${error.message}`.replaceAll(/[\r\n]+/g, " "));
  process.exitCode = 1;
}

/// 回傳 call(method, path, body)。非 2xx 會丟錯，錯誤物件上帶 status。
export function ascClient() {
  const [keyId, issuerId, keyPath] = requireEnv("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8_PATH");
  const privateKey = createPrivateKey(readFileSync(keyPath, "utf8"));

  function token() {
    const now = Math.floor(Date.now() / 1000);
    const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
    const payload = base64url(
      JSON.stringify({ iss: issuerId, iat: now, exp: now + 10 * 60, aud: "appstoreconnect-v1" }),
    );
    const signature = sign("sha256", Buffer.from(`${header}.${payload}`), {
      key: privateKey,
      dsaEncoding: "ieee-p1363",
    });
    return `${header}.${payload}.${signature.toString("base64url")}`;
  }

  return async function call(method, path, body) {
    const response = await fetch(API + path, {
      method,
      headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await response.text();
    if (!response.ok) {
      const error = new Error(
        `${method} ${path.split("?")[0]} 回 ${response.status}：${appleReason(text)}`,
      );
      error.status = response.status;
      throw error;
    }
    return text ? JSON.parse(text) : null;
  };
}

/// 找 App ID，並看 App Group 開了沒。缺的會把名字相近的列出來，多半是登記時打錯一個字。
export async function findBundleId(call, identifier) {
  // filter[identifier] 是開頭比對，所以再比一次全名
  const found = await call(
    "GET",
    `/v1/bundleIds?filter[identifier]=${encodeURIComponent(identifier)}&limit=200`,
  );
  const bundleId = found.data.find((item) => item.attributes.identifier === identifier);
  if (!bundleId) {
    // 紀錄是公開的，別的 app 不列，列開頭一樣的就好
    const near = await call("GET", "/v1/bundleIds?filter[identifier]=org.domyweb.bai&limit=200");
    const listed = near.data.map((item) => item.attributes.identifier).join("、");
    throw new Error(
      `Apple 後台沒有 App ID ${identifier}。先做 docs/上架指南.md 步驟 4。` +
        `名字相近的有：${listed || "一個都沒有"}。`,
    );
  }
  const capabilities = await call("GET", `/v1/bundleIds/${bundleId.id}/bundleIdCapabilities`);
  if (!capabilities.data.some((item) => item.attributes.capabilityType === "APP_GROUPS")) {
    throw new Error(
      `App ID ${identifier} 還沒勾 App Groups。到 developer.apple.com → Identifiers → 點它 → 勾 App Groups → ` +
        `Configure 選 ${APP_GROUP} → Save。`,
    );
  }
  return bundleId;
}

function appleReason(text) {
  try {
    return JSON.parse(text)
      .errors.map((item) => `${item.code} ${item.title} ${item.detail ?? ""}`.trim())
      .join("；")
      .slice(0, 1000);
  } catch {
    return "（沒有附說明）";
  }
}
