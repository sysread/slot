package slot;

# ABSTRACT: A simple, comple-time way to declare a class

use v5.10;
use strict;
use warnings;
no strict 'refs';
use Carp;

my %CLASS;
my $DEBUG;

sub import {
  my $caller = caller;
  my $class  = shift;
  my $name   = shift;

  if ($name eq '-debug') {
    $DEBUG = 1;
    return;
  }

  my ($type, %param) = (@_ % 2 == 0)
    ? (undef, @_)
    : @_;

  croak "slot ${name}'s type is invalid"
    if defined $type
    && !ref $type
    && !$type->can('inline_check')
    && !$type->can('check');

  my $rw  = $param{rw}  // 0;
  my $req = $param{req} // 0;
  my $def = $param{def};

  if ($def && $type) {
    croak "default value for $name is not a valid $type"
      unless $type->check(ref $def eq 'CODE' ? $def->() : $def);
  }

  unless (exists $CLASS{$caller}) {
    $CLASS{$caller} = {
      slot  => {},
      slots => [],
      ctor  => undef,
    };

    *{ $caller . '::new' } = sub {
      my ($class, @args) = @_;
      my $ctor = _build_ctor($caller);
      my $acc  = join "\n", map{ $CLASS{$caller}{slot}{$_}{acc} } @{ $CLASS{$caller}{slots} };
      my $pkg  = qq{
package $caller;
BEGIN {
use Carp;
no warnings 'redefine';
$ctor
$acc
};
      };

      if ($DEBUG) {
        print "\n";
        print "================================================================================\n";
        print "# slot generated the following code:\n";
        print "================================================================================\n";
        print "$pkg\n";
        print "================================================================================\n";
        print "# end of slot-generated code\n";
        print "================================================================================\n";
        print "\n";
      }

      eval $pkg;
      $@ && die $@;
      $class->new(@args);
    };
  }

  $CLASS{$caller}{slot}{$name} = {
    type => $type,
    rw   => $rw,
    req  => $req,
    def  => $def,
  };

  $CLASS{$caller}{slot}{$name}{acc}
    = $rw ? _build_setter($caller, $name)
          : _build_getter($caller, $name);

  push @{ $CLASS{$caller}{slots} }, $name;
}

sub _build_ctor {
  my $class = shift;

  my $code = q{
sub new \{
  my $class = shift;
  my $param = @_ == 1 ? $_[0] : {@_};
  my $self  = bless {}, $class;
  $self->init($param);
  $self;
\};

};

  $code .= _build_init($class);
  return $code;
}

sub _build_init {
  my $class = shift;
  my $code  = q{
sub init \{
  my ($self, $param) = @_;
};

  if (@{$class . '::ISA'} && $class->SUPER::can('init')) {
    $code .= "  \$self->SUPER::init(\$param);\n";
  }

  foreach my $name (@{ $CLASS{$class}{slots} }) {
    my $slot = $CLASS{$class}{slot}{$name};

    if ($slot->{req} && !defined $slot->{def}) {
      $code .= "  croak '$name is a required field' unless exists \$param->{$name};\n";
    }

    if ($slot->{type}) {
      my $check = $slot->{type}->inline_check("\$param->{$name}");

      $code .= qq{
  if (exists \$param->{$name}) {
    $check || croak '$name did not pass validation as a $slot->{type}';
  }
};
    }

    if (defined $slot->{def}) {
      if (ref $slot->{def} eq 'CODE') {
        $code .= "  \$self->{$name} = exists \$param->{$name} ? \$param->{$name} : \$CLASS{$class}{slot}{$name}{def}->(\$self)";
      }
      else {
        $code .= "  \$self->{$name} = exists \$param->{$name} ? \$param->{$name} : \$CLASS{$class}{slot}{$name}{def}";
      }
    } else {
      $code .= "  \$self->{$name} = \$param->{$name}";
    }

    $code .= ";\n";
  }

  $code .= "}\n";

  return $code;
}

sub _build_getter {
  my ($class, $name) = @_;
  return qq{
sub $name \{
  croak "$name is protected" if \@_ > 1;
  return \$_[0]->{$name};
\};
  };
}

sub _build_setter {
  my ($class, $name) = @_;
  my $slot = $CLASS{$class}{slot}{$name};

  my $code = qq{
sub $name \{
  if (\@_ > 1) \{
    croak 'usage: \$self->$name | \$self->$name(\$new_value)'
      if \@_ != 2;
};

  if ($slot->{type}) {
    my $check = $slot->{type}->inline_check('$_[1]');
    $code .= "    $check || croak 'value did not pass validation as a $slot->{type}';\n";
  }

  $code .= qq{
    \$_[0]->{$name} = \$_[1];
  \}

  \$_[0]->{$name};
\}
};

  return $code;
}

=head1 SYNOPSIS

  package Point;
  use Types::Standard -types;

  use slot x => Int, rw => 1, req => 1;
  use slot y => Int, rw => 1, req => 1;
  use slot z => Int, rw => 1, def => 0;

  1;

  my $p = Point->new(x => 10, y => 20);
  $p->x(30); # x is set to 30
  $p->y;     # 20
  $p->z;     # 0

=head1 DESCRIPTION

Similar to the L<fields> pragma, C<slot> declares individual fields in a class,
building a constructor and slot accessor methods.

Although not nearly as full-featured as L<other|Moose> L<solutions|Moo>,
C<slot> is light-weight, fast, works with basic Perl objects, and imposes no
dependencies outside of the Perl core distribution. Currently, only the unit
tests require non-core packages.

C<slot> is intended or use with Perl's bare metal objects. It provides a simple
mechanism for building accessor and constructor code at compile time.

It does I<not> provide inheritance; that is done by setting C<@ISA> or via
the C<base> or C<parent> pragmas.

It does I<not> provide method wrappers; that is done with the C<SUPER>
pseudo-class.

It I<does> build a constructor method, C<new>, with support for default and
required slots as keyword arguments and type validation of caller-supplied
values.

It I<does> build accesor methods (reader or combined reader/writer, using the
slot's name) for each slot declared, with support for type validation.

=head2 CONSTRUCTOR

C<slot> generates a constructor method named C<new>. If there is already an
existing method with that name, it may be overwritten, depending on the order
in which C<slot> was imported.

Because slots are declared individually, the constructor as well as the
accessor methods are generated on the first call to C<new>.

=head2 DECLARING SLOTS

The pragma itself accepts two positional parameters: the slot name and optional
type. The type is validated during construction and in the setter, if the slot
is read-write.

Slot names must be valid perl identifiers suitable for subroutine names. Types
must be an instance of a class that supports the C<check> and C<inline_check>
methods (see L<Type::Tiny/Inlining methods>).

=head1 OPTIONS

=head2 rw

When true, the accessor method accepts a single parameter to modify the slot
value. If the slot declares a type, the accessor will croak if the new value
does not validate.

=head2 req

When true, this constructor will croak if the slot is missing from the named
parameters passed to the constructor. If the slot also declares a
L<default value|/def>, this attribute is moot.

=head2 def

When present, this value or code ref which returns a value is used as the
default if the slot is missing from the named parameters passed to the
constructor.

If the default is a code ref which generates a value and a type is specified,
note that the code ref will be called during compilation to validate its type
rather than re-validating it with every accessor call.

=head1 DEBUGGING

Adding C<use slot -debug> to your class will cause C<slot> to print the
generated constructor and accessor code when C<new> is first called.

=cut

1;
