#!/usr/bin/perl
# 발주 이력(구매통계 xlsx → TSV) → 품목코드별 집계 JSON
use strict; use warnings; use utf8;
binmode(STDOUT, ":encoding(UTF-8)");

my $TSV = shift or die "usage: buyagg.pl stat.tsv\n";
sub nk { my $v = shift // ""; $v = uc $v; $v =~ s/[^A-Z0-9]//g; return $v; }
sub esc { my $s = shift // ""; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/[\r\n\t]+/ /g; return $s; }
sub top { my $h = shift; my @k = sort { $h->{$b} <=> $h->{$a} || $a cmp $b } keys %$h; return $k[0] // ""; }

my (%it, $sheet, @hdr);
open my $f, '<:encoding(UTF-8)', $TSV or die;
while (<$f>) {
  chomp;
  if (/^### SHEET (\d+)/) { $sheet = $1; @hdr = (); next; }
  next unless defined $sheet && $sheet == 1;
  my @c = split /\t/, $_, -1;
  if (!@hdr) { @hdr = @c if ($c[0] // "") eq "No"; next; }
  next unless ($c[0] // "") =~ /^\d+$/;

  my $code = $c[10] // "";
  my $k = nk($code);
  next unless $code =~ m{^\s*[A-Za-z]};            # 00·99 같은 임시코드 제외

  my $price = ($c[12] // "") =~ /^\d+(\.\d+)?$/ ? 0 + $c[12] : undef;
  my $qty   = ($c[13] // "") =~ /^\d+(\.\d+)?$/ ? 0 + $c[13] : 0;
  my $amt   = ($c[14] // "") =~ /^\d+(\.\d+)?$/ ? 0 + $c[14] : 0;
  my $date  = $c[1] // "";

  my $r = $it{$k} ||= { code => $code, name => "", n => 0, qty => 0, amt => 0,
                        first => "", last => "", lp => undef, mn => undef, mx => undef,
                        ven => {}, biz => {}, kind => {}, dept => {}, hist => [] };
  $r->{n}++;
  $r->{qty} += $qty;
  $r->{amt} += $amt;
  $r->{name} = $c[11] if ($c[11] // "") ne "" && length($c[11]) > length($r->{name});
  $r->{first} = $date if $date && ($r->{first} eq "" || $date lt $r->{first});
  if ($date && ($r->{last} eq "" || $date gt $r->{last})) { $r->{last} = $date; $r->{lp} = $price; }
  if (defined $price) {
    $r->{mn} = $price if !defined $r->{mn} || $price < $r->{mn};
    $r->{mx} = $price if !defined $r->{mx} || $price > $r->{mx};
  }
  $r->{ven}{  $c[9]  }++ if ($c[9]  // "") ne "";
  $r->{biz}{  $c[4]  }++ if ($c[4]  // "") ne "";
  $r->{kind}{ $c[5]  }++ if ($c[5]  // "") ne "";
  $r->{dept}{ $c[21] }++ if ($c[21] // "") ne "";
  push @{ $r->{hist} }, [ $date, $price, $qty, ($c[9] // ""), ($c[21] // "") ];
}
close $f;

my @out;
for my $k (sort keys %it) {
  my $r = $it{$k};
  my @all = sort { ($b->[0] // "") cmp ($a->[0] // "") } @{ $r->{hist} };   # 최신순

  # 연도별 집계 — 그 해 가장 최근 단가 · 발주 횟수 · 금액
  my %yr;
  for my $x (@all) {
    my $y = substr($x->[0] // "", 0, 4);
    next unless $y =~ /^\d{4}$/;
    my $s = $yr{$y} ||= { p => undef, n => 0, amt => 0 };
    $s->{p} = $x->[1] if !defined $s->{p} && defined $x->[1];   # 최신순이라 처음 것이 그 해 최근값
    $s->{n}++;
    $s->{amt} += ($x->[1] // 0) * ($x->[2] // 0);
  }
  my $yjson = "{" . join(",", map {
    '"' . $_ . '":[' . (defined $yr{$_}{p} ? $yr{$_}{p} : 'null') . ',' . $yr{$_}{n} . ',' . $yr{$_}{amt} . ']'
  } sort keys %yr) . "}";

  my @h = @all[0 .. ($#all > 2 ? 2 : $#all)];              # 상세용 최근 3건
  my @kv = (
    '"y":' . $yjson,
    '"k":"'    . esc($k) . '"',
    '"code":"' . esc($r->{code}) . '"',
    '"name":"' . esc($r->{name}) . '"',
    '"n":'     . $r->{n},
    '"qty":'   . $r->{qty},
    '"amt":'   . $r->{amt},
    '"first":"'. esc($r->{first}) . '"',
    '"last":"' . esc($r->{last}) . '"',
    (defined $r->{lp} ? '"lp":' . $r->{lp} : ()),
    (defined $r->{mn} ? '"mn":' . $r->{mn} : ()),
    (defined $r->{mx} ? '"mx":' . $r->{mx} : ()),
    '"ven":"'  . esc(top($r->{ven}))  . '"',
    '"biz":"'  . esc(top($r->{biz}))  . '"',
    '"kind":"' . esc(top($r->{kind})) . '"',
    '"dept":"' . esc(top($r->{dept})) . '"',
    '"h":['    . join(",", map { '["' . esc($_->[0]) . '",' . (defined $_->[1] ? $_->[1] : 'null') .
                                ',' . $_->[2] . ',"' . esc($_->[3]) . '","' . esc($_->[4]) . '"]' } @h) . ']',
  );
  push @out, "{" . join(",", @kv) . "}";
}
print "[\n", join(",\n", @out), "\n]\n";
print STDERR "items=" . scalar(@out) . "\n";
