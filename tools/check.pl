#!/usr/bin/perl
# 발주 이력 정합성 점검 — ERP 이관 누락으로 보이는 줄을 찾는다
#   규칙1  단가 x 수량 != 금액        (수량이 안 넘어왔거나 부가세 기준이 섞임)
#   규칙2  수량 1 인데 단가가 그 품목 중앙값의 5배 이상  (총액이 단가 칸에 들어옴)
use strict; use warnings; use utf8;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");

my $TSV = shift or die "usage: check.pl stat.tsv\n";

my (@rows, %byitem, $sheet, @hdr);
open my $f, '<:encoding(UTF-8)', $TSV or die "열 수 없습니다: $TSV\n";
while (<$f>) {
  chomp;
  if (/^### SHEET (\d+)/) { $sheet = $1; @hdr = (); next; }
  next unless defined $sheet && $sheet == 1;
  my @c = split /\t/, $_, -1;
  if (!@hdr) { @hdr = @c if ($c[0] // "") eq "No"; next; }
  next unless ($c[0] // "") =~ /^\d+$/;

  my $code = $c[10] // "";
  next unless $code =~ m{^\s*[A-Za-z]};                 # 00·99 임시코드 제외

  my $num = sub { my $v = shift // ""; $v =~ s/[,\s]//g; return $v =~ /^\d+(\.\d+)?$/ ? 0 + $v : undef };
  my $price = $num->($c[12]);
  my $qty   = $num->($c[13]);
  my $amt   = $num->($c[14]);
  next unless defined $price && defined $qty && defined $amt;

  my $r = {
    no => $c[0], date => $c[1] // "", biz => $c[4] // "", ord => $c[6] // "",
    ven => $c[9] // "", code => $code, name => $c[11] // "",
    price => $price, qty => $qty, amt => $amt,
  };
  push @rows, $r;
  push @{ $byitem{$code} }, $r;
}
close $f;

# 품목별 중앙값 — 수량이 2개 이상인 줄만 믿는다 (그 줄들은 단가가 진짜 단가)
my %med;
for my $code (keys %byitem) {
  my @p = sort { $a <=> $b } map { $_->{price} } grep { $_->{qty} >= 2 && $_->{price} > 0 } @{ $byitem{$code} };
  next unless @p;
  $med{$code} = $p[ int(@p / 2) ];
}

my @bad;
for my $r (@rows) {
  my @why;
  my $calc = $r->{price} * $r->{qty};
  push @why, "금액불일치"  if abs($calc - $r->{amt}) > 1;
  my $m = $med{ $r->{code} };
  push @why, "수량1_고단가" if $r->{qty} == 1 && $m && $r->{price} >= $m * 5;
  next unless @why;
  $r->{why}  = join("+", @why);
  $r->{calc} = $calc;
  $r->{med}  = $m;
  push @bad, $r;
}

@bad = sort { $b->{amt} <=> $a->{amt} } @bad;

print join("\t", qw(사유 발주일 구매번호 업체명 품목코드 품목명 단가 수량 단가x수량 발주금액 차액 품목중앙값)), "\n";
for my $r (@bad) {
  print join("\t",
    $r->{why}, $r->{date}, $r->{ord}, $r->{ven}, $r->{code}, $r->{name},
    $r->{price}, $r->{qty}, $r->{calc}, $r->{amt}, $r->{calc} - $r->{amt},
    (defined $r->{med} ? $r->{med} : "")), "\n";
}

my %cnt;
$cnt{ $_->{why} }++ for @bad;
print STDERR "전체 ", scalar(@rows), "행 중 이상 ", scalar(@bad), "행\n";
print STDERR "  $_ : $cnt{$_}행\n" for sort keys %cnt;
