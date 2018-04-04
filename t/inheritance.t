package P1;
use Types::Standard -types;
use prop x => Int, rw => 1;
use prop y => Int, rw => 1;
1;

package P2;
use Types::Standard -types;
use parent -norequire, 'P1';
use prop z => Int, rw => 1;
1;

package P3;
use Types::Standard -types;
use parent -norequire, 'P1';
use prop x => StrMatch[qr/[13579]$/], rw => 0, req => 1;
use prop y => StrMatch[qr/[13579]$/], rw => 1;
use prop z => sub{1} & StrMatch[qr/[13579]$/], rw => 1; # ensure non-inlined types work
1;


package main;
use strict;
use warnings;
no warnings 'once';
use Test::More;

is_deeply \@P1::PROPS, [qw(x y)],   'P1 @PROPS';
is_deeply \@P2::PROPS, [qw(x y z)], 'P2 @PROPS';
is_deeply \@P3::PROPS, [qw(x y z)], 'P3 @PROPS';

ok my $p2 = P2->new(x => 10, y => 20, z => 30), 'ctor';
is $p2->x, 10, 'get prop: x';
is $p2->y, 20, 'get prop: y';
is $p2->z, 30, 'get prop: z';
ok $p2->isa('P2'), 'isa P2';
ok $p2->isa('P1'), 'isa P1';
ok do{ local $@; eval{ P2->new(x => 10, y => 20, z => 'foo') }; $@ }, 'ctor: dies on invalid prop type';
ok do{ local $@; eval{ P2->new(x => 'foo', y => 20, z => 30) }; $@ }, 'ctor: dies on invalid parent prop type';

ok(do{ local $@; eval{ P3->new(x => 10, y => 20, z => 30) }; $@ }, 'ctor: dies on stricter child type');

ok(P3->new(x => 'a7', y => '39', z => '0x35'), 'ctor: ok on less strict child type');
ok(do{ local $@; eval{ P3->new(y => '39', z => '0x35') }; $@ }, 'ctor: dies on stricter child req');
ok(do{ my $p = P3->new(x => 'a7', y => '39', z => '0x35'); local $@; eval{ $p->x(45) }; $@ }, 'setter: dies on stricter child rw');

done_testing;
