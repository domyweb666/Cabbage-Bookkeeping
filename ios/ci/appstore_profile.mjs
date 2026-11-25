// 向 Apple 申請上架用描述檔，裝到這台機器上，給 archive 和 exportArchive 手動簽章用。
// 每次都刪掉同名的舊描述檔再建一張，App ID 之後多勾了能力，新的才會帶到。
//
// App 和小工具各一張（asc_api.mjs 的 TARGETS）。只碰名字完全一樣、而且綁在那個 App ID 的。
// 名字一樣但綁別的 app 就停下來，一張都不刪。憑證只讀，不申請也不撤銷。
//
// 環境變數：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8_PATH、SIGN_DIR
// SIGN_DIR/cert_serial 由 import_dist_cert.sh 寫好（鑰匙圈那張發佈憑證的序號，十六進位）
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { APP_GROUP, ascClient, findBundleId, reportFailure, requireEnv, TARGETS } from "./asc_api.mjs";

const normalizeSerial = (serial) => serial.trim().toUpperCase().replace(/^0+/, "");

async function findCertificate(call, serial) {
  const certificates = await call(
    "GET",
    "/v1/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION&limit=200",
  );
  const certificate = certificates.data.find(
    (item) => normalizeSerial(item.attributes.serialNumber ?? "") === serial,
  );
  if (!certificate) {
    throw new Error(
      `Apple 後台 ${certificates.data.length} 張發佈憑證裡，沒有一張跟 .p12 同序號。` +
        "這張 .p12 可能被撤銷了，或 API 金鑰屬於另一個帳號。",
    );
  }
  return certificate;
}

/// 找出要換掉的舊描述檔。只核對，不刪；有一張不是我們的就丟錯
async function findOldProfiles(call, { bundleId, profileName }) {
  const existing = await call(
    "GET",
    `/v1/profiles?filter[name]=${encodeURIComponent(profileName)}&limit=200`,
  );
  const sameName = existing.data.filter((item) => item.attributes.name === profileName);
  for (const profile of sameName) {
    const owner = await call("GET", `/v1/profiles/${profile.id}/bundleId`);
    const isOurs =
      owner?.data?.attributes?.identifier === bundleId &&
      profile.attributes.profileType === "IOS_APP_STORE";
    if (!isOurs) {
      throw new Error(
        `有一張也叫「${profileName}」的描述檔，但不是 ${bundleId} 的上架用描述檔。` +
          "沒有刪任何東西，請到後台看一下。",
      );
    }
  }
  return sameName;
}

/// 建一張、核對裡面有 App Group、裝起來。回傳裝到哪裡
async function createProfile(call, { bundleId, profileName }, bundleResource, certificate) {
  const created = await call("POST", "/v1/profiles", {
    data: {
      type: "profiles",
      attributes: { name: profileName, profileType: "IOS_APP_STORE" },
      relationships: {
        bundleId: { data: { type: "bundleIds", id: bundleResource.id } },
        certificates: { data: [{ type: "certificates", id: certificate.id }] },
      },
    },
  });
  const { uuid, profileContent, expirationDate } = created.data.attributes;
  if (!/^[0-9A-Za-z-]+$/.test(uuid)) throw new Error("Apple 回的描述檔編號格式不對");
  const content = Buffer.from(profileContent, "base64");
  // API 查得到有沒有勾 App Groups，查不到勾了哪一個。描述檔裡的 plist 是明文，直接找
  if (!content.includes(`<string>${APP_GROUP}</string>`)) {
    throw new Error(
      `${bundleId} 勾了 App Groups，但沒有選 ${APP_GROUP}。到 developer.apple.com → Identifiers → 點它 → ` +
        "App Groups 右邊的 Configure → 勾那一個 → Save，再重跑一次。",
    );
  }
  // Xcode 16 起描述檔換了位置，兩邊都放
  const paths = [
    "Library/Developer/Xcode/UserData/Provisioning Profiles",
    "Library/MobileDevice/Provisioning Profiles",
  ].map((folder) => join(homedir(), folder, `${uuid}.mobileprovision`));
  for (const path of paths) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, content);
  }
  console.log(`描述檔 ${profileName} 裝好了，到期日 ${expirationDate}`);
  return paths;
}

try {
  const [signDir] = requireEnv("SIGN_DIR");
  const call = ascClient();
  const serial = normalizeSerial(readFileSync(join(signDir, "cert_serial"), "utf8"));
  if (!/^[0-9A-F]+$/.test(serial)) throw new Error("憑證序號讀不到");

  // 兩個 App ID、憑證、舊描述檔全部核對過才開始刪，有一樣不對就一張都不動
  const certificate = await findCertificate(call, serial);
  const jobs = [];
  for (const target of TARGETS) {
    const bundleResource = await findBundleId(call, target.bundleId);
    jobs.push({ target, bundleResource, old: await findOldProfiles(call, target) });
  }
  for (const { target, old } of jobs) {
    for (const profile of old) {
      await call("DELETE", `/v1/profiles/${profile.id}`);
      console.log(`刪掉舊的描述檔 ${target.profileName}`);
    }
  }
  const installed = [];
  for (const { target, bundleResource } of jobs) {
    installed.push(...(await createProfile(call, target, bundleResource, certificate)));
    // 每裝一張就記下來，中途失敗 cleanup_signing.sh 也刪得掉
    writeFileSync(join(signDir, "installed_profiles"), `${installed.join("\n")}\n`);
  }
} catch (error) {
  reportFailure(error);
}
