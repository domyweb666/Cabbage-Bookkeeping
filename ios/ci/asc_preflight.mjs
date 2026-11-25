// 打包前先問 Apple：金鑰能不能用、兩個 App ID 和 App Group 好了沒、app 記錄建了沒、這個 build 號有沒有用過。只讀不寫。
// 環境變數：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8_PATH、BUILD_NUMBER
import { ascClient, BUNDLE_ID, findBundleId, reportFailure, requireEnv, TARGETS } from "./asc_api.mjs";

try {
  const [buildNumber] = requireEnv("BUILD_NUMBER");
  if (!/^[1-9][0-9]*$/.test(buildNumber)) throw new Error("BUILD_NUMBER 要是正整數");
  const call = ascClient();

  for (const target of TARGETS) await findBundleId(call, target.bundleId);

  const apps = await call(
    "GET",
    `/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&fields[apps]=bundleId&limit=200`,
  );
  const app = apps.data.find((item) => item.attributes.bundleId === BUNDLE_ID);
  if (!app) {
    throw new Error(
      `App Store Connect 沒有 ${BUNDLE_ID} 這個 app。先做 docs/上架指南.md 步驟 5。`,
    );
  }

  const builds = await call(
    "GET",
    `/v1/builds?filter[app]=${app.id}&fields[builds]=version&sort=-uploadedDate&limit=200`,
  );
  const highest = builds.data
    .map((item) => Number.parseInt(item.attributes.version, 10))
    .filter(Number.isFinite)
    .reduce((max, number) => Math.max(max, number), 0);
  if (Number(buildNumber) <= highest) {
    throw new Error(
      `build ${buildNumber} 沒有比 Apple 那邊最大的 ${highest} 大。` +
        "重跑舊的那次會拿到舊號碼，請重新按一次 Run workflow。",
    );
  }
  console.log(
    `金鑰可用，兩個 App ID 都開了 App Groups，app 記錄在。Apple 那邊最大的 build 是 ${highest}，這次是 ${buildNumber}。`,
  );
} catch (error) {
  reportFailure(error);
}
