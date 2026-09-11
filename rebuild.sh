#!/usr/bin/env bash
# 원본 단가 파일 → catalog.json → index.html 재생성
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/.."                       # 2026_단가계약
BOX="$SRC/단가계약 대상"
RAW="$(mktemp -d)"; trap 'rm -rf "$RAW"' EXIT

echo "1/3  엑셀 읽는 중…"
perl "$HERE/tools/xlsx2tsv.pl" "$BOX/(주)나무_2026 FITI시험연구원 단가 리스트_260224.xlsx"      > "$RAW/namu.tsv"
perl "$HERE/tools/xlsx2tsv.pl" "$BOX/2025 FITI시험연구원 단가 리스트_(주)인재시스텍.xlsx"        > "$RAW/injae.tsv"
perl "$HERE/tools/xlsx2tsv.pl" "$BOX/복사본 에이비넥소 리스트_250204_단가입력중.xlsx"            > "$RAW/abnexo.tsv"
perl "$HERE/tools/xlsx2tsv.pl" "$BOX/Metal Consumables 가격 조정 대상 품목 리스트_20260804.xlsx" > "$RAW/metal.tsv"
perl "$HERE/tools/xlsx2tsv.pl" "$SRC/휴텍스.xlsx"                                                > "$RAW/hutex.tsv"

echo "2/3  통합 카탈로그 만드는 중…"
perl "$HERE/tools/build.pl" "$RAW" > "$HERE/catalog.json"

echo "3/3  index.html 갱신 중…"
perl -e '
  local $/;
  open my $h,"<:raw",$ARGV[0] or die; my $html=<$h>; close $h;
  open my $c,"<:raw",$ARGV[1] or die; my $json=<$c>; close $c;
  $json =~ s/\s+$//;
  $html =~ s{(const BASE = )\[.*?\](;\n)}{$1$json$2}s or die "BASE 배열을 찾지 못했습니다\n";
  open my $o,">:raw",$ARGV[0] or die; print $o $html; close $o;
' "$HERE/index.html" "$HERE/catalog.json"

echo "완료 — $(perl -ne '$n++ while /"id":"/g; END{print $n}' "$HERE/catalog.json")건"
