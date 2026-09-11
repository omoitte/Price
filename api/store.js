// 수정분·이력 서버 저장소 (Vercel Blob, 비공개)
// GET  /api/store  → { overrides, added, deleted, history }
// POST /api/store  → { overrides, added, deleted, historyAppend:[...] }
//   overrides/added/deleted 는 통째로 교체, history 는 append-only 로 누적.
import { put, get } from "@vercel/blob";

const PATH = "unitprice/store.json";
const EMPTY = { overrides: {}, added: [], deleted: {}, history: [], updatedAt: 0 };
const MAX_HISTORY = 20000;

async function readStore() {
  try {
    const r = await get(PATH, { access: "private", useCache: false });
    if (!r || r.statusCode !== 200) return { ...EMPTY };
    const j = JSON.parse(await new Response(r.stream).text());
    return {
      overrides: j.overrides || {},
      added: Array.isArray(j.added) ? j.added : [],
      deleted: j.deleted || {},
      history: Array.isArray(j.history) ? j.history : [],
      updatedAt: j.updatedAt || 0,
    };
  } catch {
    return { ...EMPTY };          // 아직 한 번도 저장 안 됨
  }
}

function body(req) {
  if (!req.body) return {};
  if (typeof req.body === "string") { try { return JSON.parse(req.body); } catch { return {}; } }
  return req.body;
}

export default async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");

  if (!process.env.BLOB_READ_WRITE_TOKEN && !process.env.BLOB_STORE_ID) {
    return res.status(501).json({
      error: "blob_not_configured",
      message: "Vercel 프로젝트에 Blob 스토어를 연결하세요 (Storage → Create Database → Blob).",
    });
  }

  try {
    if (req.method === "GET") return res.status(200).json(await readStore());

    if (req.method === "POST") {
      const b = body(req);
      const cur = await readStore();
      const add = Array.isArray(b.historyAppend) ? b.historyAppend : [];
      const seen = new Set(cur.history.map(h => h.hid));
      const merged = cur.history.concat(add.filter(h => h && h.hid && !seen.has(h.hid)));

      const next = {
        overrides: b.overrides && typeof b.overrides === "object" ? b.overrides : cur.overrides,
        added: Array.isArray(b.added) ? b.added : cur.added,
        deleted: b.deleted && typeof b.deleted === "object" ? b.deleted : cur.deleted,
        history: merged.slice(-MAX_HISTORY),
        updatedAt: Date.now(),
      };

      await put(PATH, JSON.stringify(next), {
        access: "private", allowOverwrite: true, addRandomSuffix: false,
        contentType: "application/json",
      });
      return res.status(200).json({ ok: true, history: next.history.length, updatedAt: next.updatedAt });
    }

    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "method_not_allowed" });
  } catch (e) {
    return res.status(500).json({ error: "store_failed", message: String((e && e.message) || e) });
  }
}
