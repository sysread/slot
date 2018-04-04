package P1;
use Types::Standard -types;
use prop x => Int, rw => 1;
use prop y => Int, rw => 1;
1;

package main;
use strict;
use warnings;
no warnings 'once';
use Test::More;

eval q{
package P2;
use Types::Standard -types;
use parent -norequire, 'P1';
use prop z => Int, rw => 1;
1;
};

ok my $p = P2->new(x => 10, y => 10, z => 10), 'ctor';
ok $p->isa('P1'), 'isa';
is_deeply \@P2::PROPS, [qw(x y z)], '@PROPS';

done_testing;
