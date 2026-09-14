#!/usr/bin/perl
# 업체별 단가 파일(xlsx/pdf) → 통합 카탈로그 JSON
use strict; use warnings;
use utf8;
binmode(STDOUT, ":encoding(UTF-8)");

my $RAW = shift or die "usage: build.pl <rawdir>\n";

sub rows {                      # TSV 읽기 (### SHEET 줄은 시트 경계)
  my ($f) = @_;
  open my $fh, '<:encoding(UTF-8)', "$RAW/$f" or die "$f: $!";
  my (@out, $sheet);
  while (<$fh>) {
    chomp;
    if (/^### SHEET (\d+)/) { $sheet = $1; next; }
    next unless /\S/;
    push @out, { s => $sheet, c => [split /\t/, $_, -1] };
  }
  close $fh; return @out;
}
# 엑셀에서 "값 없음" 표시로 쓰는 대시(- – — －)는 빈칸으로 본다
sub cell {
  my ($r, $i) = @_;
  my $v = $r->{c}[$i];
  return "" unless defined $v;
  $v =~ s/^\s+|\s+$//g;
  return "" if $v =~ /^[-\x{2013}\x{2014}\x{FF0D}\s]*$/;
  return $v;
}
sub num  {
  my $v = shift // "";
  return undef if $v =~ /^[-\x{2013}\x{2014}\x{FF0D}\s]*$/;
  $v =~ s/[^0-9.\-]//g;
  return $v eq "" || $v eq "-" ? undef : 0 + $v;
}
sub norm { my $v = shift // ""; $v = uc $v; $v =~ s/[^A-Z0-9]//g; return $v; }   # 코드 정규화(하이픈 제거)
sub esc  { my $s = shift // ""; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/[\r\n\t]+/ /g; return $s; }

my @items;
my $id = 0;
sub add {
  my (%a) = @_;
  return unless ($a{name} // "") ne "" || ($a{code} // "") ne "";
  $id++;
  push @items, { id => "I$id", %a };
}

# ── (주)나무 2026 ──
for my $r (rows("namu.tsv")) {
  next unless $r->{s} == 1;
  my $no = cell($r, 0);
  next unless $no =~ /^\d+$/;
  add(vendor => "퍼킨엘머 소모품", sup => "(주)나무", year => 2026,
      code => cell($r,1), name => cell($r,2), partno => cell($r,3),
      list => num(cell($r,4)), price => num(cell($r,5)),
      adj => num(cell($r,6)), note => cell($r,7),
      src => "(주)나무_2026 FITI시험연구원 단가 리스트_260224.xlsx");
}

# ── (주)인재시스텍 2025 ──
for my $r (rows("injae.tsv")) {
  next unless $r->{s} == 1;
  my $no = cell($r, 0);
  next unless $no =~ /^\d+$/;
  add(vendor => "퍼킨엘머 소모품", sup => "(주)인재시스텍", year => 2025,
      code => cell($r,1), name => cell($r,2), partno => cell($r,3),
      list => num(cell($r,4)), price => num(cell($r,5)), note => cell($r,6),
      src => "2025 FITI시험연구원 단가 리스트_(주)인재시스텍.xlsx");
}

# ── 섬유시험 소모품 · 에이비넥소 (연도별 단가 컬럼) ──
# 비에스티앤씨도 같은 섬유시험 소모품이라 단가표를 받으면 아래 블록을 복사해
# sup 만 바꿔 추가하면 같은 구분으로 나란히 비교된다.
for my $r (rows("abnexo.tsv")) {
  next unless $r->{s} == 1;
  my $no = cell($r, 0);
  next unless $no =~ /^\d+$/;
  my $p26 = num(cell($r,8)); my $p25 = num(cell($r,7)); my $p24 = num(cell($r,6));
  my $price = defined $p26 ? $p26 : (defined $p25 ? $p25 : $p24);
  my $yr    = defined $p26 ? 2026 : (defined $p25 ? 2025 : 2024);
  add(vendor => "섬유시험 소모품", sup => "에이비넥소", year => $yr,
      code => cell($r,1), name => cell($r,2), partno => cell($r,3),
      maker => cell($r,4), price => $price,
      p24 => $p24, p25 => $p25, p26 => $p26, note => cell($r,9),
      src => "복사본 에이비넥소 리스트_250204_단가입력중.xlsx");
}

# ── (주)휴텍스 ──
for my $r (rows("hutex.tsv")) {
  next unless $r->{s} == 1;
  my $no = cell($r, 0);
  next unless $no =~ /^\d+$/;
  add(vendor => "(주)휴텍스", year => 2026,
      code => cell($r,1), name => cell($r,2), partno => cell($r,4),
      spec => cell($r,3), price => num(cell($r,8)),
      note => join(" ", grep { $_ ne "" } (cell($r,9), cell($r,11))),
      src => "휴텍스.xlsx");
}

# ── Metal Consumables 가격조정 (2026-07-01 시행) ──
for my $r (rows("metal.tsv")) {
  next unless $r->{s} == 1;
  my $pn = cell($r, 0);
  next if $pn eq "" || $pn =~ /^P\/N$/i || $pn =~ /Effective/i;
  add(vendor => "퍼킨엘머 소모품", sup => "Metal Consumables", year => 2026.5,
      partno => $pn, name => cell($r,1),
      list => num(cell($r,4)), price => num(cell($r,5)),
      note => "2026-07-01 개정 최종가",
      src => "Metal Consumables 가격 조정 대상 품목 리스트_20260804.xlsx");
}

# ── 에코프런티어 견적서 (PDF에서 읽음) ──
# 견적서에는 품목코드가 없어 발주 이력과 안 붙는다. 제품번호·가격이 일치하는
# 사내 품목코드를 직접 지정해 묶는다. (DMF-Y100 → B050130396, DMF-C200 → B050070045)
add(vendor => "에코프런티어", year => 2026, partno => "DMF-Y100", code => "B050130396",
    name => "물벼룩 보조먹이 (YCT)", spec => "100ml/PK", price => 44000,
    note => "견적번호 EF견 260805Y-01 · 유효 2026-12-31 · 냉장(냉동) 배송",
    src => "에코프런티어_26년도 견적서.pdf");
add(vendor => "에코프런티어", year => 2026, partno => "DMF-C200", code => "B050070045",
    name => "물벼룩 주먹이 (chlorella)", spec => "200ml/PK", price => 50000,
    note => "견적번호 EF견 260805Y-01 · 유효 2026-12-31 · 냉장(냉동) 배송",
    src => "에코프런티어_26년도 견적서.pdf");

# ── 제품번호로 FITI 품목코드 채우기 ──
# Metal Consumables·에코프런티어처럼 품목코드 없이 제품번호만 있는 행은,
# 같은 제품번호를 쓰는 다른 업체 행에서 코드를 가져온다.
my %pn2code;
for my $it (@items) {
  next unless ($it->{code} // "") ne "" && ($it->{partno} // "") ne "";
  $pn2code{ norm($it->{partno}) } //= $it->{code};
}
my $filled = 0;
for my $it (@items) {
  next if ($it->{code} // "") ne "";
  my $pk = norm($it->{partno} // "");
  next unless $pk && $pn2code{$pk};
  $it->{code} = $pn2code{$pk};
  $it->{codesrc} = "제품번호 매칭";
  $filled++;
}
print STDERR "code filled by partno: $filled\n";

# ── 정규화 키 부여 ──
for my $it (@items) {
  $it->{key}  = norm($it->{code});
  $it->{pkey} = norm($it->{partno});
}

@items = grep { $_->{vendor} ne "__DROP__" } @items;

# ── JSON 출력 ──
my @f = qw(id vendor sup year code codesrc key partno pkey name spec maker list price adj p24 p25 p26 note src);
print "[\n";
my @lines;
for my $it (@items) {
  my @kv;
  for my $k (@f) {
    my $v = $it->{$k};
    next if !defined $v || $v eq "";
    push @kv, ($k =~ /^(year|list|price|adj|p24|p25|p26)$/ && $v =~ /^-?[\d.]+$/)
      ? "\"$k\":$v" : "\"$k\":\"" . esc($v) . "\"";
  }
  push @lines, "{" . join(",", @kv) . "}";
}
print join(",\n", @lines), "\n]\n";
print STDERR "items=" . scalar(@items) . "\n";
