// 소모품 가격검색 — 외부 연동용 검색 API
//
// 업무포털의 소모품 카드가 이 API 를 불러 검색 결과 미리보기를 띄웁니다.
// 앱 화면(index.html)은 인라인 데이터로 자체 검색하므로 이 API 를 쓰지 않습니다.
//
//   GET /api/search?q=카본&limit=8
//   → { "q": "카본", "total": 23, "items": [ { name, code, partno, maker, price, year } ] }

const CATALOG_PATH = '/catalog.json';   // 정적으로 서빙되는 단가 카탈로그

let CACHE = null;         // 같은 인스턴스에서 재사용
let CACHE_AT = 0;
const TTL_MS = 10 * 60 * 1000;

async function loadCatalog(req) {
  if (CACHE && Date.now() - CACHE_AT < TTL_MS) return CACHE;

  const host = req.headers['x-forwarded-host'] || req.headers.host;
  const proto = req.headers['x-forwarded-proto'] || 'https';
  const res = await fetch(`${proto}://${host}${CATALOG_PATH}`);
  if (!res.ok) throw new Error(`catalog ${res.status}`);

  const raw = await res.json();
  CACHE = Array.isArray(raw) ? raw : [];
  CACHE_AT = Date.now();
  return CACHE;
}

// 검색어를 공백으로 쪼개 모든 조각이 들어간 항목만 남깁니다(AND).
function makeMatcher(q) {
  const terms = String(q).toLowerCase().split(/\s+/).filter(Boolean);
  return (hay) => terms.every((t) => hay.includes(t));
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=600');

  if (req.method === 'OPTIONS') return res.status(204).end();

  const q = String(req.query?.q || '').trim();
  const limit = Math.min(Math.max(parseInt(req.query?.limit, 10) || 8, 1), 50);

  if (q.length < 2) {
    return res.status(200).json({ q, total: 0, items: [], message: '두 글자 이상 입력해 주세요.' });
  }

  try {
    const catalog = await loadCatalog(req);
    const match = makeMatcher(q);

    const hits = [];
    for (const it of catalog) {
      const hay = [it.name, it.code, it.partno, it.vendor, it.sup]
        .filter(Boolean).join(' ').toLowerCase();
      if (match(hay)) hits.push(it);
    }

    // 같은 품목코드가 여러 해에 걸쳐 있으면 최신 연도 하나만 남깁니다.
    const best = new Map();
    for (const it of hits) {
      const k = it.code || it.partno || it.name;
      const prev = best.get(k);
      if (!prev || (Number(it.year) || 0) > (Number(prev.year) || 0)) best.set(k, it);
    }

    const items = [...best.values()]
      .sort((a, b) => (Number(b.year) || 0) - (Number(a.year) || 0)
                   || String(a.name || '').localeCompare(String(b.name || ''), 'ko'))
      .slice(0, limit)
      .map((it) => ({
        name: it.name || '',
        code: it.code || '',
        partno: it.partno || '',
        maker: it.vendor || '',
        supplier: it.sup || '',
        price: Number(it.price) || null,
        list: Number(it.list) || null,
        year: Number(it.year) || null
      }));

    return res.status(200).json({ q, total: best.size, items });
  } catch (error) {
    console.error('[price search api error]', error);
    return res.status(500).json({ q, total: 0, items: [], message: '검색 중 오류가 발생했습니다.' });
  }
}
