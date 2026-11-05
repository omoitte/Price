// 발주 이력 저장소 (Vercel Blob, 비공개)
//
//   GET  /api/purchases        → { rows:[...], asOf, count, source }
//   POST /api/purchases        → { key, asOf, rows:[...] }  (전체 교체)
//
// 왜 있나 — 전에는 발주 이력이 index.html 안에 `const BUY = [...]` 로 박혀 있어,
// 매달 자료를 바꾸려면 rebuild.sh 를 돌리고 3.3MB 짜리 index.html 을 다시 배포해야 했습니다.
// 이제 화면이 이 API 를 먼저 보고, 없으면 박혀 있는 값을 씁니다. 배포 없이 갱신됩니다.
//
// 바꾸는 쪽은 열어 두지 않습니다 — 20,000줄짜리 단가 자료를 통째로 바꾸는 입구라
// 환경변수 PRICE_EDIT_KEY 를 넣어야 POST 가 열립니다. (씨마켓 BID_EDIT_KEY 와 같은 방식)
import { put, get } from "@vercel/blob";

const PATH = "unitprice/purchases.json";
const PATH_PREV = "unitprice/purchases.prev.json";   // 덮기 직전 한 벌
const MAX_BYTES = 40 * 1024 * 1024;     // 과하게 큰 요청은 받지 않습니다

function blobOpt() {
  const pick = (suffix) => {
    if (process.env["BLOB" + suffix]) return process.env["BLOB" + suffix];
    const k = Object.keys(process.env).find((n) => n.endsWith(suffix) && process.env[n]);
    return k ? process.env[k] : undefined;
  };
  const token = pick("_READ_WRITE_TOKEN");
  const storeId = pick("_STORE_ID");
  const o = {};
  if (token) o.token = token;
  else if (storeId) o.storeId = storeId;
  return o;
}

async function readRows() {
  try {
    const r = await get(PATH, { access: "private", useCache: false, ...blobOpt() });
    if (!r || !r.stream) return null;
    const j = JSON.parse(await new Response(r.stream).text());
    if (!j || !Array.isArray(j.rows)) return null;
    return j;
  } catch {
    return null;                       // 아직 한 번도 올린 적 없음
  }
}

function body(req) {
  if (!req.body) return {};
  if (typeof req.body === "string") { try { return JSON.parse(req.body); } catch { return {}; } }
  return req.body;
}

export default async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");

  const opt = blobOpt();
  if (!opt.token && !opt.storeId) {
    return res.status(501).json({
      error: "blob_not_configured",
      message: "Vercel 프로젝트에 Blob 스토어를 연결하세요 (Storage → Connect Store → Blob → Redeploy).",
    });
  }

  try {
    if (req.method === "GET") {
      const j = await readRows();
      if (!j) return res.status(200).json({ rows: [], asOf: "", count: 0, source: "none" });
      return res.status(200).json({
        rows: j.rows, asOf: j.asOf || "", count: j.rows.length, source: "blob",
      });
    }

    if (req.method === "POST") {
      /* 열쇠(PRICE_EDIT_KEY)를 넣어 두면 열쇠가 맞아야 올라갑니다.
         안 넣었으면(11-04 사용자 지시 「해결해」) 열쇠 없이 받되, 엉뚱한 파일로 덮이지 않게
         ① 품목 1,000개 미만은 거부 ② 덮기 직전 자료를 unitprice/purchases.prev.json 으로 백업합니다. */
      const need = process.env.PRICE_EDIT_KEY;
      const b = body(req);
      if (need && String(b.key || "") !== String(need)) {
        return res.status(401).json({ error: "bad_key", message: "열쇠가 맞지 않습니다." });
      }
      if (!Array.isArray(b.rows) || !b.rows.length) {
        return res.status(400).json({ error: "no_rows", message: "올릴 자료가 비어 있습니다." });
      }
      const MIN_ROWS = 1000;
      const okRows = b.rows.filter((x) => x && (x.k || x.code) && x.name).length;
      if (okRows < MIN_ROWS) {
        return res.status(400).json({
          error: "too_few",
          message: `품목이 ${okRows.toLocaleString("ko-KR")}개뿐입니다. 구매통계 전체 파일(품목 ${MIN_ROWS.toLocaleString("ko-KR")}개 이상)만 받습니다.`,
        });
      }
      const prev = await readRows();
      if (prev && prev.rows.length) {
        await put(PATH_PREV, JSON.stringify(prev), {
          access: "private", allowOverwrite: true, addRandomSuffix: false,
          contentType: "application/json", ...opt,
        });
      }

      const payload = JSON.stringify({
        rows: b.rows,
        asOf: String(b.asOf || "").slice(0, 10),
        savedAt: new Date().toISOString(),
      });
      if (payload.length > MAX_BYTES) {
        return res.status(413).json({ error: "too_big", message: "자료가 너무 큽니다." });
      }

      await put(PATH, payload, {
        access: "private", allowOverwrite: true, addRandomSuffix: false,
        contentType: "application/json", ...opt,
      });
      return res.status(200).json({ ok: true, count: b.rows.length, asOf: b.asOf || "" });
    }

    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "method_not_allowed" });
  } catch (e) {
    return res.status(500).json({ error: "purchases_failed", message: String((e && e.message) || e) });
  }
}
