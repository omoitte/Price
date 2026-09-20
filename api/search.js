// 소모품 가격검색 — 외부 연동용 검색 API
//
// 업무포털의 소모품 카드가 이 API 를 불러 검색 결과 미리보기를 띄웁니다.
// 앱 화면(index.html)은 인라인 데이터로 자체 검색하므로 이 API 를 쓰지 않습니다.
//
//   GET /api/search?q=카본&limit=8
//   → { q, total, items:[ { name, code, partno, maker, supplier, price, list, year, src, ... } ] }
//
// 데이터가 두 벌입니다. 한쪽만 보면 검색이 헛돕니다.
//   catalog.json   단가계약 카탈로그 — 계약단가(price)·정가(list)·품번이 있음
//   purchases.json 실구매 이력 집계 — 토너·용지 같은 일반 소모품은 여기에만 있음
// 두 벌을 모두 읽어 품목코드로 합칩니다.

const CATALOG_PATH  = '/catalog.json';
const PURCHASE_PATH = '/purchases.json';

let CACHE = null;         // 같은 인스턴스에서 재사용
let CACHE_AT = 0;
const TTL_MS = 10 * 60 * 1000;

async function getJson(req, path) {
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  const proto = req.headers['x-forwarded-proto'] || 'https';
  const res = await fetch(`${proto}://${host}${path}`);
  if (!res.ok) throw new Error(`${path} ${res.status}`);
  return res.json();
}

function yearOf(dateStr) {
  const y = parseInt(String(dateStr || '').slice(0, 4), 10);
  return Number.isFinite(y) ? y : null;
}

// 두 파일을 하나의 공통 모양으로 펼칩니다.
async function loadIndex(req) {
  if (CACHE && Date.now() - CACHE_AT < TTL_MS) return CACHE;

  // 한쪽이 없어도 나머지로 검색이 되게 각각 따로 받습니다.
  const [catRes, purRes] = await Promise.allSettled([
    getJson(req, CATALOG_PATH),
    getJson(req, PURCHASE_PATH)
  ]);

  const rows = [];

  if (catRes.status === 'fulfilled' && Array.isArray(catRes.value)) {
    for (const it of catRes.value) {
      rows.push({
        src: 'catalog',
        name: it.name || '',
        code: it.code || it.key || '',
        partno: it.partno || '',
        maker: it.vendor || '',
        supplier: it.sup || '',
        price: Number(it.price) || null,
        list: Number(it.list) || null,
        year: Number(it.year) || null,
        count: null,
        lastDate: '',
        kind: '',
        hay: [it.name, it.code, it.partno, it.vendor, it.sup]
          .filter(Boolean).join(' ').toLowerCase()
      });
    }
  }

  if (purRes.status === 'fulfilled' && Array.isArray(purRes.value)) {
    for (const it of purRes.value) {
      rows.push({
        src: 'purchase',
        name: it.name || '',
        code: it.code || it.k || '',
        partno: '',
        maker: it.ven || '',            // 실구매는 제조사 대신 거래처를 보여줍니다.
        supplier: it.ven || '',
        price: Number(it.lp) || null,   // lp = 최종단가
        list: null,
        year: yearOf(it.last),
        count: Number(it.n) || null,    // n = 구매 건수
        lastDate: it.last || '',
        kind: it.kind || '',
        hay: [it.name, it.code, it.ven, it.kind]
          .filter(Boolean).join(' ').toLowerCase()
      });
    }
  }

  if (!rows.length) throw new Error('no data source available');

  CACHE = rows;
  CACHE_AT = Date.now();
  return CACHE;
}

// 검색어를 공백으로 쪼개 모든 조각이 들어간 항목만 남깁니다(AND).
function makeMatcher(q) {
  const terms = String(q).toLowerCase().split(/\s+/).filter(Boolean);
  return (hay) => terms.every((t) => hay.includes(t));
}

// 같은 품목이 두 파일에 다 있으면 한 줄로 합칩니다.
// 계약단가가 있는 catalog 쪽을 기준으로 두고, 실구매의 건수·최근일자를 얹습니다.
function merge(a, b) {
  const base  = a.src === 'catalog' ? a : b;
  const other = base === a ? b : a;
  return {
    ...base,
    partno: base.partno || other.partno,
    maker: base.maker || other.maker,
    supplier: base.supplier || other.supplier,
    price: base.price != null ? base.price : other.price,
    list: base.list != null ? base.list : other.list,
    count: base.count != null ? base.count : other.count,
    lastDate: base.lastDate || other.lastDate,
    kind: base.kind || other.kind,
    year: Math.max(Number(base.year) || 0, Number(other.year) || 0) || null,
    src: a.src === b.src ? a.src : 'both'
  };
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
    const index = await loadIndex(req);
    const match = makeMatcher(q);

    // 품목코드(없으면 품목명)로 묶습니다.
    const best = new Map();
    for (const it of index) {
      if (!match(it.hay)) continue;
      const k = it.code || it.partno || it.name;
      const prev = best.get(k);
      best.set(k, prev ? merge(prev, it) : it);
    }

    // 계약단가가 있는 것 → 최근 것 → 이름순.
    const items = [...best.values()]
      .sort((a, b) =>
        (b.src === 'purchase' ? 0 : 1) - (a.src === 'purchase' ? 0 : 1)
        || (Number(b.year) || 0) - (Number(a.year) || 0)
        || String(a.name || '').localeCompare(String(b.name || ''), 'ko'))
      .slice(0, limit)
      .map(({ hay, ...rest }) => rest);

    return res.status(200).json({ q, total: best.size, items });
  } catch (error) {
    console.error('[price search api error]', error);
    return res.status(500).json({ q, total: 0, items: [], message: '검색 중 오류가 발생했습니다.' });
  }
}
