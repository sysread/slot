package slot;

# ABSTRACT: Simple, efficient, comple-time class declaration

use strict;
use warnings;
no strict 'refs';
no warnings 'redefine';
use Carp;

our $XS;

BEGIN {
  unless (defined $XS) {
    eval 'use Class::XSAccessor';
    $XS = $@ ? 0 : 1;
  }
}

my %CLASS;
my %TYPE;
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

  my $rw  = $param{rw};
  my $req = $param{req};

  croak "slot ${name}'s type is invalid"
    if defined $type
    && !ref $type
    && !$type->can('inline_check')
    && !$type->can('check');

  if (exists $param{def} && $type) {
    croak "default value for $name is not a valid $type"
      unless $type->check(ref $param{def} eq 'CODE' ? $param{def}->() : $param{def});
  }

  unless (exists $CLASS{$caller}) {
    $CLASS{$caller} = {
      slot  => {},
      slots => [],
      ctor  => undef,
      init  => sub{
        # Ensure any accessor methods defined by $caller's parent class(es)
        # have been built.
        foreach (@{ $caller . '::ISA' }) {
          if (exists $CLASS{$_} && defined $CLASS{$_}{init}) {
            $CLASS{$_}{init}->();
          }
        }

        # Build constructor and accessor methods
        my $ctor = _build_ctor($caller);

        my $acc = join "\n", map{
            $rw ? _build_setter($caller, $_)
                : _build_getter($caller, $_)
          }
          @{ $CLASS{$caller}{slots} };

        my $pkg  = qq{
package $caller;
use Carp;
no warnings 'redefine';
BEGIN {
$ctor
$acc
}
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

        # Install constructor and accessor methods
        eval $pkg;
        $@ && die $@;

        delete $CLASS{$caller}{init};
      },
    };

    # Temporary definition of new that includes code to initialize the class as
    # configured for slots.
    *{ $caller . '::new' } = sub {
      $CLASS{$_[0]}{init}->();
      goto $_[0]->can('new');
    };
  }

  $CLASS{$caller}{slot}{$name} = {};

  if (defined $type) {
    $CLASS{$caller}{slot}{$name}{type} = "$type";
    $TYPE{"$type"} = $type;
  }

  foreach (qw(def req rw)) {
    $CLASS{$caller}{slot}{$name}{$_} = $param{$_}
      if exists $param{$_};
  }

  *{ $caller . '::get_slots' } = \&get_slots;

  push @{ $CLASS{$caller}{slots} }, $name;
}

#-------------------------------------------------------------------------------
# Constructor
#-------------------------------------------------------------------------------
sub _build_ctor {
  my $class = shift;

  my $code = qq{
sub new \{
  my \$class = shift;
  my \$self  = bless { \@_ }, \$class;
};

  my $slots = $class->get_slots;

  foreach my $name (keys %$slots) {
    my $slot  = $slots->{$name};
    my $req   = $slot->{req};
    my $def   = $slot->{def};
    my $type  = $TYPE{$slot->{type}};
    my $check = $type->inline_check("\$self->{$name}")
      if defined $type;

    if ($req && !defined $def) {
      $code .= "  croak '$name is a required field' unless exists \$self->{$name};\n";
    }

    if ($check) {
      $code .= qq{
  croak '${class}::$name did not pass validation as a $type'
    unless !exists \$self->{$name}
        || $check;
};
    }

    if (defined $def) {
      $code .= "  \$self->{$name} = ";

      if (ref $def eq 'CODE') {
        $code .= "\$CLASS{$class}{slot}{$name}{def}->(\$self)";
      }
      else {
        $code .= "\$CLASS{$class}{slot}{$name}{def}";
      }

      $code .= " unless exists \$self->{$name};\n";
    }
  }

  $code .= qq{
  \$self;
\};

};

  return $code;
}

#-------------------------------------------------------------------------------
# Settings
#-------------------------------------------------------------------------------
sub get_slots {
  my ($class) = @_;
  my %slots;

  foreach ($class, @{ $class . '::ISA' }) {
    foreach my $slot (@{$CLASS{$_}{slots}}) {
      if (!exists $slots{$slot}) {
        $slots{$slot} = $CLASS{$_}{slot}{$slot};
      }
      else {
        foreach my $cfg (qw(rw req def)) {
          if (!exists $slots{$slot}{$cfg} && exists $CLASS{$_}{slot}{$slot}{$cfg}) {
            $slots{$slot}{$cfg} = $CLASS{$_}{slot}{$slot}{$cfg};
          }
        }

        if (!exists $slots{$slot}{type} && exists $CLASS{$_}{slot}{$slot}{type}) {
          $slots{$slot}{type} = $TYPE{$CLASS{$_}{slot}{$slot}{type}};
        }
      }
    }
  }

  return \%slots;
}

#-------------------------------------------------------------------------------
# Read-only accessor
#-------------------------------------------------------------------------------
sub _build_getter {
  my ($class, $name) = @_;
  if ($XS) {
    return _build_getter_xs($class, $name);
  } else {
    return _build_getter_pp($class, $name);
  }
}

sub _build_getter_pp {
  my ($class, $name) = @_;
  return "sub $name { return \$_[0]->{$name} if defined wantarray; }\n";
}

sub _build_setter_pp {
  my ($class, $name) = @_;
  my $slot  = $class->get_slots->{$name};
  my $type  = $TYPE{$slot->{type}} if $slot->{type};
  my $check = $type->inline_check('$_[1]') if defined $type;

  my $code = "sub $name {\n  if (\@_ > 1) {\n";

  if ($check) {
    $code .= qq{
    croak '${class}::$name did not pass validation as a $type'
      unless $check;
};
  }

  $code .= qq{
    \$_[0]->{$name} = \$_[1];
  \}

  return \$_[0]->{$name}
    if defined wantarray;
\}
};
}

#-------------------------------------------------------------------------------
# Read-write accessor
#-------------------------------------------------------------------------------
sub _build_setter {
  my ($class, $name) = @_;
  if ($XS && !$CLASS{$class}{slot}{$name}{type}) {
    return _build_setter_xs($class, $name);
  } else {
    return _build_setter_pp($class, $name);
  }
}

sub _build_getter_xs {
  my ($class, $name) = @_;
  return "use Class::XSAccessor getters => {'$name' => '$name'}, replace => 1, class => '$class';\n";
}

sub _build_setter_xs {
  my ($class, $name) = @_;
  return "use Class::XSAccessor accessors => {'$name' => '$name'}, replace => 1, class => '$class';\n";
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

C<slot> is intended for use with Perl's bare metal objects. It provides a
simple mechanism for building accessor and constructor code at compile time.

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

=head1 INHERITANCE

When a class declares a slot which is also declared in the parent class, the
parent class' settings are overridden. Any options I<not> included in the
overriding class' slot declaration remain in effect in the child class.

  package A;

  use slot 'foo', rw => 1;
  use slot 'bar', req => 1, rw => 1;

  1;

  package B;

  use parent -norequire, 'A';

  use slot 'foo', req => 1; # B->foo is req, inherits rw
  use slot 'bar', rw => 0;  # B->bar inherits req, but is no longer rw

  1;

=head1 DEBUGGING

Adding C<use slot -debug> to your class will cause C<slot> to print the
generated constructor and accessor code when C<new> is first called.

=head1 PERFORMANCE

C<slot> is designed to be fast and have a low overhead. When available,
L<Class::XSAccessor> is used to generate the class accessors. This applies to
slots that are not writable or are writable but have no declared type.

A minimal benchmark on my admittedly underpowered system compares L<Moose>,
L<Moo>, and L<slot>. The test includes multiple setters using a mix of
inherited, typed and untyped, attributes. Both L<Moo> and L<slot> have access
to the installed L<Class::XSAccessor> C<v1.19>.

            Rate   moo moose  slot
  moo   355872/s    --  -51%  -63%
  moose 719424/s  102%    --  -25%
  slot  961538/s  170%   34%    --

=head1 TODO

  1. Use type->check when type->inline_check is not available

=cut

1;
