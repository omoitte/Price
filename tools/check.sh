#!/usr/bin/env bash
# 발주 이력 정합성 점검 → 이상치점검.tsv
set -euo pipefail
cd "$(dirname "$0")"

DEV="D:/Google Drive/38.구매시스템_개발/10.통계파일"
P="../단가검색-site"
RAW="$(mktemp -d)"; trap 'rm -rf "$RAW"' EXIT

echo "1/2  발주 이력 읽는 중…"
perl "$P/tools/xlsx2tsv.pl" "$DEV/구매통계_소모품_시약_구분_(2024-202608) - 수정 중.xlsx" > "$RAW/stat.tsv"

echo "2/2  점검 중…"
perl tools/check.pl "$RAW/stat.tsv" > 이상치점검.tsv

echo
echo "완료 — 이상치점검.tsv ($(($(wc -l < 이상치점검.tsv) - 1))행)"
echo
echo "금액 큰 순 20건:"
head -21 이상치점검.tsv | cut -f1,2,4,6,7,8,10 | column -t -s $'\t'
