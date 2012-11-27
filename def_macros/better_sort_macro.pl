# -- def_macro better_sort

use 5.014;
use warnings;
use strict;

say join "\n", map { "$_->[0]$_->[1]"}
sort { $a->[0] cmp $b->[0] || $a->[1] <=> $b->[1] }
map { my $alpha; my $num; ($alpha, $num) = $_ =~ /^(\w+)(\d+)/; [ $alpha, $num ]  } <>;


# -- promote_macro better_sort
# -- exit

__DATA__
a1
a2
a100
a102
b2
b3
b4
b301