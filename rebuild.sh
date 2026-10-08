#!/usr/bin/env bash
# 원본 엑셀 → catalog.json / purchases.json → index.html 재생성
# 이 폴더는 '가격 검색'만 다룹니다. 배포판 조립은 한 단계 위 배포.sh 가 합니다.
# Git Bash 에서 실행하세요 (cmd 는 perl 경로 때문에 안 됩니다).
#
# 매달 하는 일은 이것뿐입니다:
#   1) 10.통계파일 에 새 구매통계 엑셀을 넣는다  (파일명은 아무래도 됩니다 — 최신 것을 알아서 씁니다)
#   2) 이 스크립트를 돌린다
#   3) index.html 을 배포한다
set -euo pipefail
cd "$(dirname "$0")"

DEV="E:/Google Drive/38.구매시스템_개발/10.통계파일"      # 관리 원본 폴더
BOX="../단가계약 대상"                                     # 공급사 단가표 엑셀 폴더
RAW="$(mktemp -d)"; trap 'rm -rf "$RAW"' EXIT

# ── 발주 이력 엑셀 찾기 ───────────────────────────────────────────────
# 파일명에 기간이 들어가 매달 바뀌므로(202608 → 202609 …) 최신 수정본을 자동으로 고릅니다.
STAT="$(ls -t "$DEV"/구매통계_소모품_시약_구분_*.xlsx 2>/dev/null | head -1 || true)"
if [ -z "$STAT" ]; then
  echo "!! 발주 이력 엑셀을 찾지 못했습니다."
  echo "   찾은 곳 : $DEV"
  echo "   이름 규칙: 구매통계_소모품_시약_구분_*.xlsx"
  exit 1
fi
echo "발주 이력 : $(basename "$STAT")"

# ── 단가표 엑셀 확인 ─────────────────────────────────────────────────
# build.pl 이 파일마다 열 구조를 따로 읽으므로 이름이 정해져 있습니다.
NAMU="$BOX/(주)나무_2026 FITI시험연구원 단가 리스트_260224.xlsx"
INJAE="$BOX/2025 FITI시험연구원 단가 리스트_(주)인재시스텍.xlsx"
ABNEXO="$BOX/복사본 에이비넥소 리스트_250204_단가입력중.xlsx"
METAL="$BOX/Metal Consumables 가격 조정 대상 품목 리스트_20260804.xlsx"
HUTEX="../휴텍스.xlsx"

MISSING=""
for f in "$NAMU" "$INJAE" "$ABNEXO" "$METAL" "$HUTEX"; do
  [ -f "$f" ] || MISSING="$MISSING
  - $f"
done

if [ -n "$MISSING" ]; then
  echo
  echo "!! 단가표 엑셀이 없어 단가계약 카탈로그(catalog.json)는 건너뜁니다:$MISSING"
  echo
  echo "   기존 catalog.json 을 그대로 두고 발주 이력만 갱신합니다."
  echo "   단가표를 갱신하시려면 위 파일들을 제자리에 두고 다시 돌리세요."
  echo
  SKIP_CATALOG=1
else
  SKIP_CATALOG=0
fi

# ── 1) 단가표 → TSV ──────────────────────────────────────────────────
if [ "$SKIP_CATALOG" = "0" ]; then
  echo "1/4  단가표 읽는 중…"
  perl tools/xlsx2tsv.pl "$NAMU"   > "$RAW/namu.tsv"
  perl tools/xlsx2tsv.pl "$INJAE"  > "$RAW/injae.tsv"
  perl tools/xlsx2tsv.pl "$ABNEXO" > "$RAW/abnexo.tsv"
  perl tools/xlsx2tsv.pl "$METAL"  > "$RAW/metal.tsv"
  perl tools/xlsx2tsv.pl "$HUTEX"  > "$RAW/hutex.tsv"
  # 독점 섬유시험 소모품 단가 — build.pl 에 블록 추가 후 주석 해제
  # perl tools/xlsx2tsv.pl "$DEV/20260225_독점섬유시험소모품단가.xlsx" > "$RAW/fiber.tsv"
else
  echo "1/4  단가표 — 건너뜀"
fi

# ── 2) 발주 이력 → TSV ───────────────────────────────────────────────
echo "2/4  발주 이력 읽는 중…"
perl tools/xlsx2tsv.pl "$STAT" > "$RAW/stat.tsv"

# 열 순서가 바뀌면 엉뚱한 칸을 읽으므로 헤더를 확인하고 멈춘다
HDR=$(grep -m1 '^No	' "$RAW/stat.tsv" || true)
EXPECT='No	발주일	년도	월	구매업무	구매구분	구매번호	구매품의일자	발주번호	업체명	품목코드	품목명	발주단가	발주수량	발주금액'
if [ "$(printf '%s' "$HDR" | cut -f1-15)" != "$EXPECT" ]; then
  echo
  echo "!! 열 순서가 예상과 다릅니다. buyagg.pl 의 열 번호를 고쳐야 합니다."
  echo "   예상: $EXPECT"
  echo "   실제: $(printf '%s' "$HDR" | cut -f1-15)"
  echo "   위 두 줄을 그대로 알려주시면 맞춰 드리겠습니다."
  exit 1
fi

# 이번 달 데이터에 무엇이 들어왔는지 미리 보여 줍니다 (구매업무 값 분포)
echo
echo "     구매업무 값 —"
awk -F'\t' 'f && $5!="" {c[$5]++} /^No\t/{f=1} END{for(k in c) printf "       %-24s %6d\n", k, c[k]}' "$RAW/stat.tsv" \
  | sort -k2 -rn | head -14
echo

# ── 3) 통합 데이터 ───────────────────────────────────────────────────
echo "3/4  통합 데이터 만드는 중…"
if [ "$SKIP_CATALOG" = "0" ]; then
  perl tools/build.pl "$RAW" > catalog.json
fi
perl tools/buyagg.pl "$RAW/stat.tsv" > purchases.json

# ── 4) index.html 에 끼워 넣기 ───────────────────────────────────────
echo "4/4  index.html 갱신 중…"
perl -e '
  local $/;
  open my $h,"<:raw","index.html" or die; my $x=<$h>; close $h;
  open my $c,"<:raw","catalog.json" or die; my $j=<$c>; close $c; $j =~ s/\s+$//;
  open my $p,"<:raw","purchases.json" or die; my $u=<$p>; close $p; $u =~ s/\s+$//;
  $x =~ s{(const BASE = )\[.*?\](;\n)}{$1$j$2}s or die "BASE 배열을 찾지 못했습니다\n";
  $x =~ s{(const BUY = )\[.*?\](;\n)}{$1$u$2}s  or die "BUY 배열을 찾지 못했습니다\n";
  open my $o,">:raw","index.html" or die; print $o $x; close $o;
'

UC=$(grep -c '단가계약' purchases.json || true)
echo
echo "완료 — 단가 $(grep -o '"id":"' catalog.json | wc -l)건 · 발주품목 $(grep -o '"k":"' purchases.json | wc -l)개"
echo "       발주 내역 $(grep -o '\["20' purchases.json | wc -l)행 · index.html $(du -h index.html | cut -f1)"
echo "       단가계약 품목 ${UC}개"
[ "$SKIP_CATALOG" = "1" ] && echo "       (catalog.json 은 이전 것을 그대로 씀)"
echo
echo "다음: index.html 을 배포하세요."
