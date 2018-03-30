package A;
use Types::Standard -types;

use slot foo => Int, rw => 1, def => 42;
use slot bar => Str, req => 1;
use slot baz => req => 1, def => 'fnord';

1;

package AB;
use Types::Standard -types;
our @ISA = qw(A);

use slot bat => ArrayRef, req => 1;

1;

package main;

use Test2::V0;
use Test2;

# Constructor
ok my $o = A->new(foo => 1, bar => 'slack', baz => 'bat'), 'ctor';

# Getters
is $o->foo, 1, 'get slot';
is $o->bar, 'slack', 'get slot';
is $o->baz, 'bat', 'get slot';

ok dies{ $o->bar('baz') }, 'ro acc dies w/ arg';
ok dies{ $o->foo(1, 2, 3) }, 'rw acc dies w/ too many args';

# Setters
is $o->foo(4), 4, 'set slot';
is $o->foo, 4, 'slot remains set';

# Validation
ok dies{ A->new(foo => 1, baz => 2) }, 'ctor dies w/o req arg';
ok dies{ A->new(bar => 'bar', foo => 'not an int') }, 'ctor dies on invalid type';

ok $o = A->new(bar => 'asdf'), 'ctor w/o def args';
is $o->foo, 42, 'get slot w/ def';
is $o->baz, 'fnord', 'get slot w/ def';
is $o->bar, 'asdf', 'get slot w/o def';

# Inheritance
ok my $p = AB->new(foo => 7, bar => 'asdf', baz => 'qwerty', bat => [1, 2, 3]), 'inherited ctor';
ok $p->isa('A'), 'isa';
is $p->foo, 7, 'get slot';
is $p->bar, 'asdf', 'get slot';
is $p->baz, 'qwerty', 'get slot';
is $p->bat, [1, 2, 3], 'get slot';

done_testing;
