#!/usr/bin/env bash
# 원본 엑셀 → catalog.json / purchases.json → index.html 재생성
# Git Bash 에서 실행하세요 (cmd 는 perl 경로 때문에 안 됩니다).
set -euo pipefail
cd "$(dirname "$0")"

# 배포판 안의 사본으로는 돌릴 수 없다 — 원본 엑셀 경로가 한 단계 어긋난다
if [ "$(basename "$PWD")" = "배포판" ]; then
  echo "!! 여기서는 못 돌립니다. 한 단계 위 '단가검색-site' 폴더의 rebuild.sh 를 쓰세요."
  echo "   (이 사본은 참고용입니다. 원본을 돌리면 이 폴더가 자동으로 갱신됩니다.)"
  exit 1
fi

DEV="D:/Google Drive/38.구매시스템_개발/10.통계파일"      # 관리 원본 폴더
BOX="../단가계약 대상"
RAW="$(mktemp -d)"; trap 'rm -rf "$RAW"' EXIT

echo "1/5  단가표 읽는 중…"
perl tools/xlsx2tsv.pl "$BOX/(주)나무_2026 FITI시험연구원 단가 리스트_260224.xlsx"      > "$RAW/namu.tsv"
perl tools/xlsx2tsv.pl "$BOX/2025 FITI시험연구원 단가 리스트_(주)인재시스텍.xlsx"        > "$RAW/injae.tsv"
perl tools/xlsx2tsv.pl "$BOX/복사본 에이비넥소 리스트_250204_단가입력중.xlsx"            > "$RAW/abnexo.tsv"
perl tools/xlsx2tsv.pl "$BOX/Metal Consumables 가격 조정 대상 품목 리스트_20260804.xlsx" > "$RAW/metal.tsv"
perl tools/xlsx2tsv.pl "../휴텍스.xlsx"                                                  > "$RAW/hutex.tsv"
# 독점 섬유시험 소모품 단가 (에이비넥소·비에스티앤씨) — build.pl 에 블록 추가 후 주석 해제
# perl tools/xlsx2tsv.pl "$DEV/20260225_독점섬유시험소모품단가.xlsx"                     > "$RAW/fiber.tsv"

echo "2/5  발주 이력 읽는 중…"
perl tools/xlsx2tsv.pl "$DEV/구매통계_소모품_시약_구분_(2024-202608) - 수정 중.xlsx" > "$RAW/stat.tsv"

# 열 순서가 바뀌면 엉뚱한 칸을 읽으므로 헤더를 확인하고 멈춘다
HDR=$(grep -m1 '^No	' "$RAW/stat.tsv" || true)
echo "   헤더: $HDR"
EXPECT='No	발주일	년도	월	구매업무	구매구분	구매번호	구매품의일자	발주번호	업체명	품목코드	품목명	발주단가	발주수량	발주금액'
if [ "$(printf '%s' "$HDR" | cut -f1-15)" != "$EXPECT" ]; then
  echo
  echo "!! 열 순서가 예상과 다릅니다. buyagg.pl 의 열 번호를 고쳐야 합니다."
  echo "   예상: $EXPECT"
  echo "   실제: $(printf '%s' "$HDR" | cut -f1-15)"
  echo "   위 두 줄을 그대로 알려주시면 맞춰 드리겠습니다."
  exit 1
fi

echo "3/5  통합 데이터 만드는 중…"
perl tools/build.pl  "$RAW"        > catalog.json
perl tools/buyagg.pl "$RAW/stat.tsv" > purchases.json

echo "4/5  index.html 갱신 중…"
perl -e '
  local $/;
  open my $h,"<:raw","index.html" or die; my $x=<$h>; close $h;
  open my $c,"<:raw","catalog.json" or die; my $j=<$c>; close $c; $j =~ s/\s+$//;
  open my $p,"<:raw","purchases.json" or die; my $u=<$p>; close $p; $u =~ s/\s+$//;
  $x =~ s{(const BASE = )\[.*?\](;\n)}{$1$j$2}s or die "BASE 배열을 찾지 못했습니다\n";
  $x =~ s{(const BUY = )\[.*?\](;\n)}{$1$u$2}s  or die "BUY 배열을 찾지 못했습니다\n";
  open my $o,">:raw","index.html" or die; print $o $x; close $o;
'

echo "5/5  배포판 갱신 중…"
mkdir -p 배포판/tools 배포판/api
cp index.html catalog.json purchases.json rebuild.sh 배포판/
cp tools/*.pl 배포판/tools/

echo "완료 — 단가 $(grep -o '"id":"' catalog.json | wc -l)건 · 발주품목 $(grep -o '"k":"' purchases.json | wc -l)개"
echo "       발주 내역 $(grep -o '\["20' purchases.json | wc -l)행 · index.html $(du -h index.html | cut -f1)"
echo
echo "GitHub 에 올릴 파일: 배포판/index.html · catalog.json · purchases.json · rebuild.sh · tools/buyagg.pl"
