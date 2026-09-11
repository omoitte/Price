#!/usr/bin/perl
# xlsx → TSV. python/openpyxl 없이 OOXML을 직접 읽는다.
# usage: perl xlsx2tsv.pl <file.xlsx> [sheetIndex(1-base, 기본 전체)]
use strict; use warnings;
use File::Temp qw(tempdir);

my ($xlsx, $only) = @ARGV;
die "usage: xlsx2tsv.pl file.xlsx [sheetNo]\n" unless $xlsx && -f $xlsx;

my $dir = tempdir(CLEANUP => 1);
system("unzip", "-qq", "-o", $xlsx, "-d", $dir) == 0 or die "unzip failed\n";

sub slurp { my $p = shift; return "" unless -f $p; local $/; open my $fh, '<:raw', $p or return ""; my $s = <$fh>; close $fh; return $s; }
sub unesc {
  my $s = shift // "";
  $s =~ s/&lt;/</g; $s =~ s/&gt;/>/g; $s =~ s/&quot;/"/g; $s =~ s/&apos;/'/g;
  $s =~ s/&#(\d+);/chr($1)/ge; $s =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge;
  $s =~ s/&amp;/&/g;
  $s =~ s/[\r\n\t]+/ /g;
  return $s;
}

# 공유 문자열
my @sst;
{
  my $x = slurp("$dir/xl/sharedStrings.xml");
  while ($x =~ /<si\b[^>]*>(.*?)<\/si>/gs) {
    my $si = $1; my $t = "";
    $t .= unesc($1) while $si =~ /<t\b[^>]*>(.*?)<\/t>/gs;
    push @sst, $t;
  }
}

# 시트 이름 ↔ 파일
my $wb = slurp("$dir/xl/workbook.xml");
my $rels = slurp("$dir/xl/_rels/workbook.xml.rels");
my %target;
while ($rels =~ /Id="([^"]+)"[^>]*Target="([^"]+)"/g) { $target{$1} = $2; }
my @sheets;
while ($wb =~ /<sheet\b([^>]*)\/?>/g) {
  my $a = $1;
  my ($nm) = $a =~ /name="([^"]*)"/;
  my ($ri) = $a =~ /r:id="([^"]*)"/;
  my $tg = $ri && $target{$ri} ? $target{$ri} : undef;
  $tg =~ s{^/xl/}{} if $tg;
  $tg =~ s{^\.?/?}{} if $tg;
  push @sheets, { name => unesc($nm), file => $tg };
}

sub colnum { my $r = shift; my $n = 0; $n = $n * 26 + (ord(uc $_) - 64) for split //, $r; return $n; }

my $idx = 0;
for my $sh (@sheets) {
  $idx++;
  next if $only && $idx != $only;
  my $path = "$dir/xl/" . ($sh->{file} // "worksheets/sheet$idx.xml");
  $path = "$dir/xl/worksheets/sheet$idx.xml" unless -f $path;
  my $x = slurp($path);
  next unless $x;
  print "### SHEET $idx: $sh->{name}\n";
  while ($x =~ /<row\b([^>]*)>(.*?)<\/row>/gs) {
    my ($ra, $body) = ($1, $2);
    my ($rn) = $ra =~ /r="(\d+)"/;
    my @cells;
    while ($body =~ /<c\b([^>]*?)(?:\/>|>(.*?)<\/c>)/gs) {
      my ($ca, $cb) = ($1, $2 // "");
      my ($ref) = $ca =~ /r="([A-Z]+)\d+"/;
      my ($ty)  = $ca =~ /t="([^"]+)"/;
      my $val = "";
      if (defined $ty && $ty eq 's') {
        my ($v) = $cb =~ /<v>(\d+)<\/v>/;
        $val = defined $v && defined $sst[$v] ? $sst[$v] : "";
      } elsif (defined $ty && $ty eq 'inlineStr') {
        $val .= unesc($1) while $cb =~ /<t\b[^>]*>(.*?)<\/t>/gs;
      } else {
        my ($v) = $cb =~ /<v>(.*?)<\/v>/s;
        $val = defined $v ? unesc($v) : "";
      }
      my $ci = $ref ? colnum($ref) : (scalar(@cells) + 1);
      $cells[$ci - 1] = $val;
    }
    next unless grep { defined $_ && $_ ne "" } @cells;
    print join("\t", map { defined $_ ? $_ : "" } @cells), "\n";
  }
}
