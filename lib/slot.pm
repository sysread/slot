package slot;

use strict;
use warnings;
no strict 'refs';
no warnings 'redefine';
use Carp;

our $VERSION = '0.01';
our %CLASS;
our %TYPE;
our $DEBUG;
our $XS;

BEGIN {
  unless (defined $XS) {
    eval 'use Class::XSAccessor';
    $XS = $@ ? 0 : 1;
  }
}

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
    && !$type->can('can_be_inlined')
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

        my $acc = '';
        foreach (@{ $CLASS{$caller}{slots} }) {
          if ($CLASS{$caller}{slot}{$_}{rw}) {
            $acc .= _build_setter($caller, $_);
          } else {
            $acc .= _build_getter($caller, $_);
          }

          $acc .= "\n";
        }

        my $slots = join ' ', map{ quote_identifier($_) }
          sort keys %{ $caller->get_slots };

        my $pkg  = qq{
package $caller;
use Carp;
no warnings 'redefine';

our \@SLOTS;

\@SLOTS = qw($slots);;

$ctor

$acc

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

    eval "CHECK { \$slot::CLASS{$caller}{init}->() if exists \$slot::CLASS{$caller}{init} }";
    $@ && die $@;

=cut
    # Temporary definition of new that includes code to initialize the class as
    # configured for slots.
    *{ $caller . '::new' } = sub {
      $CLASS{$_[0]}{init}->();
      goto $_[0]->can('new');
    };
=cut
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
    my $type  = $TYPE{$slot->{type}} if exists $slot->{type};
    my $ident = quote_identifier($name);

    if ($req && !defined $def) {
      $code .= "  croak '$ident is a required field' unless exists \$self->{'$ident'};\n";
    }

    if ($type) {
      my $check = $type->can_be_inlined
        ? $type->inline_check("\$self->{'$ident'}")
        : "\$slot::TYPE{'$type'}->check(\$self->{'$ident'})";

      $code .= qq{
  croak '${class}::$ident did not pass validation as a $type'
    unless !exists \$self->{'$ident'}
        || $check;
};
    }

    if (defined $def) {
      $code .= "  \$self->{'$ident'} = ";

      if (ref $def eq 'CODE') {
        $code .= "\$CLASS{$class}{slot}{'$ident'}{def}->(\$self)";
      }
      else {
        $code .= "\$CLASS{$class}{slot}{'$ident'}{def}";
      }

      $code .= " unless exists \$self->{'$ident'};\n";
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

sub _build_getter_xs {
  my ($class, $name) = @_;
  my $ident = quote_identifier($name);
  return "use Class::XSAccessor getters => {'$ident' => '$ident'}, replace => 1, class => '$class';\n";
}

sub _build_getter_pp {
  my ($class, $name) = @_;
  my $ident = quote_identifier($name);
  return qq{
sub $ident \{
  croak "${class}::$ident is protected"
    if \@_ > 1;

  return \$_[0]->{'$ident'}
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

sub _build_setter_xs {
  my ($class, $name) = @_;
  my $ident = quote_identifier($name);
  return "use Class::XSAccessor accessors => {'$ident' => '$ident'}, replace => 1, class => '$class';\n";
}

sub _build_setter_pp {
  my ($class, $name) = @_;
  my $slot  = $class->get_slots->{$name};
  my $type  = $TYPE{$slot->{type}} if $slot->{type};
  my $ident = quote_identifier($name);

  my $code = "sub $ident {\n  if (\@_ > 1) {\n";

  if ($type) {
    my $check = $type->can_be_inlined
      ? $type->inline_check('$_[1]')
      : "\$slot::TYPE{'$type'}->check(\$_[1])";

      $code .= qq{
    croak '${class}::$ident did not pass validation as a $type'
      unless $check;
};
  }

  $code .= qq{
    \$_[0]->{'$ident'} = \$_[1];
  \}

  return \$_[0]->{'$ident'}
    if defined wantarray;
\}
};
}

#-------------------------------------------------------------------------------
# Helpers
#-------------------------------------------------------------------------------
sub quote_identifier {
  my $ident = shift;
  $ident =~ s/([^a-zA-Z0-9_]+)/_/g;
  return $ident;
}

1;

__END__

=head1 NAME

slot - Simple, efficient, comple-time class declaration

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

=head1 @SLOTS

The C<@SLOTS> package variable is added to the declaring package and is a
list of quoted slot identifiers.

=head1 CONSTRUCTOR

C<slot> generates a constructor method named C<new>. If there is already an
existing method with that name, it may be overwritten, depending on the order
in which C<slot> was imported.

Because slots are declared individually, the constructor as well as the
accessor methods are generated on the first call to C<new>.

=head1 DECLARING SLOTS

The pragma itself accepts two positional parameters: the slot name and optional
type. The type is validated during construction and in the setter, if the slot
is read-write.

Slot names must be valid perl identifiers suitable for subroutine names. Types
must be an instance of a class that supports the C<can_be_inlined>,
C<inline_check>, and C<check> methods (see L<Type::Tiny/Inlining methods>).

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

=head1 COMPILATION PHASES

=head2 BEGIN

C<use slot> statements are evaluated by the perl interpreter at the earliest
possible moment. At this time, C<slot> is still gathering slot declarations and
the class is not fully assembled.

=head2 CHECK

All slots are assumed to be declared by the C<CHECK> phase. The first slot
declaration adds a C<CHECK> block to the package that installs all generated
accessor methods in the declaring class. This may additionally trigger any
parent classes (identified by C<@ISA>) which are not yet complete.

=head1 DEBUGGING

Adding C<use slot -debug> to your class will cause C<slot> to print the
generated constructor and accessor code just before it is evaluated.

=head1 PERFORMANCE

C<slot> is designed to be fast and have a low overhead. When available,
L<Class::XSAccessor> is used to generate the class accessors. This applies to
slots that are not writable or are writable but have no declared type.

A minimal benchmark on my admittedly underpowered system compares L<Moose>,
L<Moo>, and L<slot>. The test includes multiple setters using a mix of
inherited, typed and untyped, attributes, which ammortizes the benefit of
Class::XSAccessor to L<Moo> and L<slot>.

  |           Rate   moo moose  slot
  | moo   355872/s    --  -51%  -63%
  | moose 719424/s  102%    --  -25%
  | slot  961538/s  170%   34%    --

Oddly, L<Moo> seemed to perform better running the same test without
L<Class::XSAccessor> installed.

  |           Rate   moo moose  slot
  | moo   377358/s    --  -50%  -56%
  | moose 757576/s  101%    --  -12%
  | slot  862069/s  128%   14%    --

=head1 AUTHOR

Jeff Ober <sysread@fastmail.fm>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by Jeff Ober.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
