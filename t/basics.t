package A;
use Types::Standard -types;
use slot foo => Int, rw => 1, def => 42;
use slot bar => Str, req => 1;
use slot baz => req => 1, def => 'fnord';
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

# Setters
is $o->foo(4), 4, 'set slot';
is $o->foo, 4, 'slot remains set';

# Validation
ok(A->check_foo(40), 'check_foo: positive input');
ok(!A->check_foo('foo'), 'check_foo: negative input');

ok(A->check_bar('bar'), 'check_bar: positive input');
ok(!A->check_bar([]), 'check_bar: negative input');

ok(A->check_baz('baz'), 'check_baz: positive input');
ok(A->check_baz([]), 'check_baz: negative input');

ok dies{ A->new(foo => 1, baz => 2) }, 'ctor dies w/o req arg';
ok dies{ A->new(bar => 'bar', foo => 'not an int') }, 'ctor dies on invalid type';

ok $o = A->new(bar => 'asdf'), 'ctor w/o def args';
is $o->foo, 42, 'get slot w/ def';
is $o->baz, 'fnord', 'get slot w/ def';
is $o->bar, 'asdf', 'get slot w/o def';

done_testing;
