#!/usr/bin/env bash
# 가격 검색 데이터를 다시 만들고, 배포판(깃허브 업로드용)을 폴더로 나눠 조립한다.
#   단가검색-site/   가격 검색 소스
#   Dashboard-site/  대시보드 소스
#   배포판/          여기로 모인다
set -euo pipefail
cd "$(dirname "$0")"

P="단가검색-site"
D="Dashboard-site"
OUT="배포판"

echo "=== 1. 가격 검색 데이터 재생성"
bash "$P/rebuild.sh"

echo
echo "=== 2. 배포판 조립"
rm -rf "$OUT"
mkdir -p "$OUT"/{data,dashboard,api,tools}

# 가격 검색 — 루트
cp "$P/index.html"     "$OUT/"
cp "$P/vercel.json"    "$OUT/"
cp "$P/package.json"   "$OUT/"
cp "$P/api/store.js"   "$OUT/api/"

# 데이터 — 한 곳에만 둔다. 대시보드가 이걸 읽는다
cp "$P/catalog.json" "$P/purchases.json" "$OUT/data/"

# 대시보드 — /dashboard/
cp "$D/index.html" "$D/terminal.css" "$D/data.js" "$D/panels.js" "$OUT/dashboard/"

# 도구
cp "$P/tools/"*.pl "$OUT/tools/"
cp "$D/tools/"*.pl "$OUT/tools/"
cp "$P/rebuild.sh" "$OUT/tools/"
cp "$D/check.sh"   "$OUT/tools/"
cp 배포.sh          "$OUT/tools/"

cp README.md   "$OUT/" 2>/dev/null || true
cp .gitignore  "$OUT/" 2>/dev/null || true
cp .env.example "$OUT/" 2>/dev/null || true

echo
echo "완료 — $OUT"
find "$OUT" -type f | sed "s|^$OUT/|  |" | sort
echo
echo "  총 $(du -sh "$OUT" | cut -f1)"
echo
echo "GitHub 에는 배포판 폴더 '안의 내용물'을 올리세요 (배포판 폴더 자체를 끌면 안 됩니다)."
