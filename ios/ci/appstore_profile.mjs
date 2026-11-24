// 向 Apple 申請上架用描述檔，裝到這台機器上，給 archive 和 exportArchive 手動簽章用。
// 每次都刪掉同名的舊描述檔再建一張，App ID 之後多勾了能力，新的才會帶到。
//
// 只碰名字完全等於 PROFILE_NAME、而且綁在 BUNDLE_ID 的那一張。名字一樣但綁別的 app 就停下來，
// 一張都不刪。憑證只讀，不申請也不撤銷。
//
// 環境變數：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8_PATH、SIGN_DIR
// SIGN_DIR/cert_serial 由 import_dist_cert.sh 寫好（鑰匙圈那張發佈憑證的序號，十六進位）
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { ascClient, BUNDLE_ID, PROFILE_NAME, reportFailure, requireEnv } from "./asc_api.mjs";

const normalizeSerial = (serial) => serial.trim().toUpperCase().replace(/^0+/, "");

async function findBundleId(call) {
  const found = await call(
    "GET",
    `/v1/bundleIds?filter[identifier]=${encodeURIComponent(BUNDLE_ID)}&limit=200`,
  );
  // filter[identifier] 是開頭比對，org.domyweb.baicai.xxx 也會進來，所以再比一次全名
  const bundleId = found.data.find((item) => item.attributes.identifier === BUNDLE_ID);
  if (!bundleId) {
    throw new Error(`Apple 後台沒有 App ID ${BUNDLE_ID}。先做 docs/上架指南.md 步驟 4。`);
  }
  return bundleId;
}

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

/// 先全部核對過，有一張不對就整個停下來，才開始刪
async function removeOldProfiles(call) {
  const existing = await call(
    "GET",
    `/v1/profiles?filter[name]=${encodeURIComponent(PROFILE_NAME)}&limit=200`,
  );
  const sameName = existing.data.filter((item) => item.attributes.name === PROFILE_NAME);
  for (const profile of sameName) {
    const owner = await call("GET", `/v1/profiles/${profile.id}/bundleId`);
    const isOurs =
      owner?.data?.attributes?.identifier === BUNDLE_ID &&
      profile.attributes.profileType === "IOS_APP_STORE";
    if (!isOurs) {
      throw new Error(
        `有一張也叫「${PROFILE_NAME}」的描述檔，但不是 ${BUNDLE_ID} 的上架用描述檔。` +
          "沒有刪任何東西，請到後台看一下。",
      );
    }
  }
  for (const profile of sameName) {
    await call("DELETE", `/v1/profiles/${profile.id}`);
    console.log(`刪掉舊的描述檔 ${PROFILE_NAME}`);
  }
}

try {
  const [signDir] = requireEnv("SIGN_DIR");
  const call = ascClient();
  const serial = normalizeSerial(readFileSync(join(signDir, "cert_serial"), "utf8"));
  if (!/^[0-9A-F]+$/.test(serial)) throw new Error("憑證序號讀不到");

  // 兩樣都找得到才動描述檔
  const bundleId = await findBundleId(call);
  const certificate = await findCertificate(call, serial);
  await removeOldProfiles(call);

  const created = await call("POST", "/v1/profiles", {
    data: {
      type: "profiles",
      attributes: { name: PROFILE_NAME, profileType: "IOS_APP_STORE" },
      relationships: {
        bundleId: { data: { type: "bundleIds", id: bundleId.id } },
        certificates: { data: [{ type: "certificates", id: certificate.id }] },
      },
    },
  });
  const { uuid, profileContent, expirationDate } = created.data.attributes;
  if (!/^[0-9A-Za-z-]+$/.test(uuid)) throw new Error("Apple 回的描述檔編號格式不對");

  // Xcode 16 起描述檔換了位置，兩邊都放
  const paths = [
    "Library/Developer/Xcode/UserData/Provisioning Profiles",
    "Library/MobileDevice/Provisioning Profiles",
  ].map((folder) => join(homedir(), folder, `${uuid}.mobileprovision`));
  writeFileSync(join(signDir, "installed_profiles"), `${paths.join("\n")}\n`);
  for (const path of paths) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, Buffer.from(profileContent, "base64"));
  }
  console.log(`描述檔 ${PROFILE_NAME} 裝好了，到期日 ${expirationDate}`);
} catch (error) {
  reportFailure(error);
}
