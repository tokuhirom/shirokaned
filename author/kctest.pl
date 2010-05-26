use strict;
use warnings;
use 5.10.1;
use KyotoCabinet;

say "KyotoCabinet: $KyotoCabinet::VERSION\n";

for my $i (1..5) {
    my $capcount = 10 ** $i;
    my $db = KyotoCabinet::DB->new;
    $db->open("*#capcount=$capcount") or die;
    $db->set($_ => 1) for 1..10000;
    printf "%d\t%d\n", $capcount, $db->count;
}

