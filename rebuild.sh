#!/usr/bin/env bash
# 원본 엑셀 → catalog.json / purchases.json → index.html 재생성
# Git Bash 에서 실행하세요 (cmd 는 perl 경로 때문에 안 됩니다).
set -euo pipefail
cd "$(dirname "$0")"

DEV="D:/Google Drive/38.구매시스템_개발/10.통계파일"      # 관리 원본 폴더
BOX="../단가계약 대상"
RAW="$(mktemp -d)"; trap 'rm -rf "$RAW"' EXIT

echo "1/4  단가표 읽는 중…"
perl tools/xlsx2tsv.pl "$BOX/(주)나무_2026 FITI시험연구원 단가 리스트_260224.xlsx"      > "$RAW/namu.tsv"
perl tools/xlsx2tsv.pl "$BOX/2025 FITI시험연구원 단가 리스트_(주)인재시스텍.xlsx"        > "$RAW/injae.tsv"
perl tools/xlsx2tsv.pl "$BOX/복사본 에이비넥소 리스트_250204_단가입력중.xlsx"            > "$RAW/abnexo.tsv"
perl tools/xlsx2tsv.pl "$BOX/Metal Consumables 가격 조정 대상 품목 리스트_20260804.xlsx" > "$RAW/metal.tsv"
perl tools/xlsx2tsv.pl "../휴텍스.xlsx"                                                  > "$RAW/hutex.tsv"
# 독점 섬유시험 소모품 단가 (에이비넥소·비에스티앤씨) — build.pl 에 블록 추가 후 주석 해제
# perl tools/xlsx2tsv.pl "$DEV/20260225_독점섬유시험소모품단가.xlsx"                     > "$RAW/fiber.tsv"

echo "2/4  발주 이력 읽는 중…"
perl tools/xlsx2tsv.pl "$DEV/구매통계_소모품_시약_구분_(2024-202608) - 수정 중.xlsx" > "$RAW/stat.tsv"

echo "3/4  통합 데이터 만드는 중…"
perl tools/build.pl  "$RAW"        > catalog.json
perl tools/buyagg.pl "$RAW/stat.tsv" > purchases.json

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

echo "완료 — 단가 $(grep -o '"id":"' catalog.json | wc -l)건 · 발주품목 $(grep -o '"k":"' purchases.json | wc -l)개"
