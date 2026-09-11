#!/usr/bin/perl
# CID 인코딩 PDF → 텍스트. 폰트마다 다른 ToUnicode CMap을 각각 읽어
# /Fn Tf 로 전환해가며 디코딩한다. poppler 불필요.
use strict; use warnings;
use Compress::Zlib;
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");

my $file = shift or die "usage: pdf2txt.pl file.pdf\n";
local $/;
open my $fh, '<:raw', $file or die "$file: $!";
my $raw = <$fh>; close $fh;

# ── 객체 색인 ──
my %obj;
while ($raw =~ /(?:^|[\r\n>\s])(\d+)\s+0\s+obj\b(.*?)endobj/gs) { $obj{$1} = $2; }

sub obj_stream {
  my $n = shift;
  my $body = $obj{$n} or return undef;
  return undef unless $body =~ /stream\r?\n(.*?)endstream/s;
  my $u = Compress::Zlib::uncompress($1);
  return defined $u ? $u : $1;
}

# ── CMap 파싱 ──
sub parse_cmap {
  my $s = shift or return undef;
  my %m;
  while ($s =~ /beginbfchar(.*?)endbfchar/gs) {
    my $b = $1;
    while ($b =~ /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g) {
      my ($c, $u) = (hex($1), $2);
      my $t = ""; $t .= chr(hex($1)) while $u =~ /([0-9A-Fa-f]{4})/g;
      $m{$c} = $t;
    }
  }
  while ($s =~ /beginbfrange(.*?)endbfrange/gs) {
    my $b = $1;
    while ($b =~ /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g) {
      my ($lo, $hi, $d) = (hex($1), hex($2), hex($3));
      $m{$lo + $_} = chr($d + $_) for 0 .. ($hi - $lo);
    }
  }
  return \%m;
}

# ── 폰트 리소스명 → CMap ──
my %fontmap;
while ($raw =~ /\/Font\s*<<(.*?)>>/gs) {
  my $fd = $1;
  while ($fd =~ /\/(\w+)\s+(\d+)\s+0\s+R/g) {
    my ($res, $fo) = ($1, $2);
    next if exists $fontmap{$res};
    my $fbody = $obj{$fo} or next;
    my ($tu) = $fbody =~ /\/ToUnicode\s+(\d+)\s+0\s+R/;
    unless ($tu) {   # Type0 이면 자손 폰트를 따라간다
      my ($df) = $fbody =~ /\/DescendantFonts\s*\[\s*(\d+)\s+0\s+R/;
      ($tu) = $obj{$df} =~ /\/ToUnicode\s+(\d+)\s+0\s+R/ if $df && $obj{$df};
    }
    next unless $tu;
    my $cm = parse_cmap(obj_stream($tu));
    $fontmap{$res} = $cm if $cm && %$cm;
  }
}
die "폰트별 ToUnicode CMap을 찾지 못했습니다\n" unless %fontmap;
warn "fonts: " . join(", ", map { "$_(" . scalar(keys %{$fontmap{$_}}) . ")" } sort keys %fontmap) . "\n";

my $cur;   # 현재 폰트 cmap
sub dec {
  my $h = shift; $h =~ s/\s+//g;
  my $out = "";
  while ($h =~ /([0-9A-Fa-f]{4})/g) {
    my $c = hex($1);
    my $t = $cur && exists $cur->{$c} ? $cur->{$c} : "";
    $t = "" if $t eq "\x{ffff}";
    $out .= $t;
  }
  return $out;
}

# ── 콘텐츠 스트림 ──
my @rows;
for my $n (sort { $a <=> $b } keys %obj) {
  my $s = obj_stream($n);
  next unless defined $s && $s =~ /BT/ && $s !~ /begincmap/;
  my ($x, $y, $lx, $ly) = (0, 0, 0, 0);
  $cur = (values %fontmap)[0];
  while ($s =~ /(?:
        \/(\w+)\s+[\d.]+\s+Tf
      | <([0-9A-Fa-f\s]+)>\s*Tj
      | \[((?:[^\[\]])*)\]\s*TJ
      | ([-\d.]+)\s+([-\d.]+)\s+(?:Td|TD)
      | [-\d.]+\s+[-\d.]+\s+[-\d.]+\s+[-\d.]+\s+([-\d.]+)\s+([-\d.]+)\s+Tm
      | (T\*)
    )/gsx) {
    if (defined $1)      { $cur = $fontmap{$1} if $fontmap{$1}; }
    elsif (defined $2)   { push @rows, [$y, $x, dec($2)]; }
    elsif (defined $3)   { my $a = $3; my $t = ""; $t .= dec($1) while $a =~ /<([0-9A-Fa-f\s]+)>/g;
                           push @rows, [$y, $x, $t] if $t ne ""; }
    elsif (defined $4)   { $lx += $4; $ly += $5; ($x, $y) = ($lx, $ly); }
    elsif (defined $6)   { ($lx, $ly) = ($6, $7); ($x, $y) = ($6, $7); }
    elsif (defined $8)   { $ly -= 12; $y = $ly; }
  }
}

# ── y 좌표로 줄 묶기 ──
my %line;
for my $r (@rows) {
  next if !defined $r->[2] || $r->[2] =~ /^\s*$/;
  push @{ $line{ sprintf("%.0f", $r->[0]) } }, [$r->[1], $r->[2]];
}
for my $y (sort { $b <=> $a } keys %line) {
  my @c = sort { $a->[0] <=> $b->[0] } @{ $line{$y} };
  my ($out, $prev) = ("", undef);
  for my $q (@c) {
    $out .= "\t" if defined $prev && $q->[0] - $prev > 14;
    $out .= $q->[1];
    $prev = $q->[0];
  }
  $out =~ s/^\s+|\s+$//g;
  print $out, "\n" if $out ne "";
}
