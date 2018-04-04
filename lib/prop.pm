package prop;

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
our $LATE;

BEGIN {
  unless (defined $XS || $ENV{SLOT_NO_XS}) {
    eval 'use Class::XSAccessor';
    $XS = $@ ? 0 : 1;
  }
}

INIT {
  $LATE = 1;
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

  croak "prop ${name}'s type is invalid"
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
      prop  => {},
      props => [],
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
        foreach (@{ $CLASS{$caller}{props} }) {
          if ($CLASS{$caller}{prop}{$_}{rw}) {
            $acc .= _build_setter($caller, $_);
          } else {
            $acc .= _build_getter($caller, $_);
          }

          $acc .= "\n";
        }

        my $props = join ' ', map{ quote_identifier($_) }
          sort keys %{ $caller->get_props };

        my $pkg  = qq{
package $caller;
use Carp;
no warnings 'redefine';

our \@PROPS;

\@PROPS = qw($props);;

$ctor

$acc

};

        if ($DEBUG) {
          print "\n";
          print "================================================================================\n";
          print "# prop generated the following code:\n";
          print "================================================================================\n";
          print "$pkg\n";
          print "================================================================================\n";
          print "# end of prop-generated code\n";
          print "================================================================================\n";
          print "\n";
        }

        # Install constructor and accessor methods
        eval $pkg;
        $@ && die $@;

        delete $CLASS{$caller}{init};
      },
    };

    # Whereas with a run-time eval the definitions of all props are not yet
    # known and CHECK is not available, so methods may be installed on the
    # first call to 'new'.
    if ($LATE) {
      *{$caller . '::new'} = sub {
        $prop::CLASS{$caller}{init}->();
        goto $caller->can('new');
      };
    }
    # Compile-time generation allows use of CHECK to install our methods once
    # the entire class has been loaded.
    else {
      eval qq{
CHECK {
  \$prop::CLASS{$caller}{init}->()
    if exists \$prop::CLASS{$caller}{init};
}
};

      $@ && die $@;
    }
  }

  $CLASS{$caller}{prop}{$name} = {};

  if (defined $type) {
    $CLASS{$caller}{prop}{$name}{type} = "$type";
    $TYPE{"$type"} = $type;
  }

  foreach (qw(def req rw)) {
    $CLASS{$caller}{prop}{$name}{$_} = $param{$_}
      if exists $param{$_};
  }

  *{ $caller . '::get_props' } = \&get_props;

  push @{ $CLASS{$caller}{props} }, $name;
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

  my $props = $class->get_props;

  foreach my $name (keys %$props) {
    my $prop  = $props->{$name};
    my $req   = $prop->{req};
    my $def   = $prop->{def};
    my $type  = $TYPE{$prop->{type}} if exists $prop->{type};
    my $ident = quote_identifier($name);

    if ($req && !defined $def) {
      $code .= "  croak '$ident is a required field' unless exists \$self->{'$ident'};\n";
    }

    if ($type) {
      my $check = $type->can_be_inlined
        ? $type->inline_check("\$self->{'$ident'}")
        : "\$prop::TYPE{'$type'}->check(\$self->{'$ident'})";

      $code .= qq{
  croak '${class}::$ident did not pass validation as a $type'
    unless !exists \$self->{'$ident'}
        || $check;
};
    }

    if (defined $def) {
      $code .= "  \$self->{'$ident'} = ";

      if (ref $def eq 'CODE') {
        $code .= "\$CLASS{$class}{prop}{'$ident'}{def}->(\$self)";
      }
      else {
        $code .= "\$CLASS{$class}{prop}{'$ident'}{def}";
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
sub get_props {
  my ($class) = @_;
  my %props;

  foreach ($class, @{ $class . '::ISA' }) {
    foreach my $prop (@{$CLASS{$_}{props}}) {
      if (!exists $props{$prop}) {
        $props{$prop} = $CLASS{$_}{prop}{$prop};
      }
      else {
        foreach my $cfg (qw(rw req def)) {
          if (!exists $props{$prop}{$cfg} && exists $CLASS{$_}{prop}{$prop}{$cfg}) {
            $props{$prop}{$cfg} = $CLASS{$_}{prop}{$prop}{$cfg};
          }
        }

        if (!exists $props{$prop}{type} && exists $CLASS{$_}{prop}{$prop}{type}) {
          $props{$prop}{type} = $TYPE{$CLASS{$_}{prop}{$prop}{type}};
        }
      }
    }
  }

  return \%props;
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
  if ($XS && !$CLASS{$class}{prop}{$name}{type}) {
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
  my $prop  = $class->get_props->{$name};
  my $type  = $TYPE{$prop->{type}} if $prop->{type};
  my $ident = quote_identifier($name);

  my $code = "sub $ident {\n  if (\@_ > 1) {\n";

  if ($type) {
    my $check = $type->can_be_inlined
      ? $type->inline_check('$_[1]')
      : "\$prop::TYPE{'$type'}->check(\$_[1])";

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

prop - Simple, efficient, comple-time class declaration

=head1 SYNOPSIS

  package Point;
  use Types::Standard -types;

  use prop x => Int, rw => 1, req => 1;
  use prop y => Int, rw => 1, req => 1;
  use prop z => Int, rw => 1, def => 0;

  1;

  my $p = Point->new(x => 10, y => 20);
  $p->x(30); # x is set to 30
  $p->y;     # 20
  $p->z;     # 0

=head1 DESCRIPTION

Similar to the L<fields> pragma, C<prop> declares individual fields in a class,
building a constructor and prop accessor methods.

Although not nearly as full-featured as L<other|Moose> L<solutions|Moo>,
C<prop> is light-weight, fast, works with basic Perl objects, and imposes no
dependencies outside of the Perl core distribution. Currently, only the unit
tests require non-core packages.

C<prop> is intended for use with Perl's bare metal objects. It provides a
simple mechanism for building accessor and constructor code at compile time.

It does I<not> provide inheritance; that is done by setting C<@ISA> or via
the C<base> or C<parent> pragmas.

It does I<not> provide method wrappers; that is done with the C<SUPER>
pseudo-class.

It I<does> build a constructor method, C<new>, with support for default and
required props as keyword arguments and type validation of caller-supplied
values.

It I<does> build accesor methods (reader or combined reader/writer, using the
prop's name) for each prop declared, with support for type validation.

=head1 @PROPS

The C<@PROPS> package variable is added to the declaring package and is a
list of quoted prop identifiers.

=head1 CONSTRUCTOR

C<prop> generates a constructor method named C<new>. If there is already an
existing method with that name, it may be overwritten, depending on the order
in which C<prop> was imported.

Because props are declared individually, the constructor as well as the
accessor methods are generated on the first call to C<new>.

=head1 DECLARING PROPS

The pragma itself accepts two positional parameters: the prop name and optional
type. The type is validated during construction and in the setter, if the prop
is read-write.

Prop names must be valid perl identifiers suitable for subroutine names. Types
must be an instance of a class that supports the C<can_be_inlined>,
C<inline_check>, and C<check> methods (see L<Type::Tiny/Inlining methods>).

=head1 OPTIONS

=head2 rw

When true, the accessor method accepts a single parameter to modify the prop
value. If the prop declares a type, the accessor will croak if the new value
does not validate.

=head2 req

When true, this constructor will croak if the prop is missing from the named
parameters passed to the constructor. If the prop also declares a
L<default value|/def>, this attribute is moot.

=head2 def

When present, this value or code ref which returns a value is used as the
default if the prop is missing from the named parameters passed to the
constructor.

If the default is a code ref which generates a value and a type is specified,
note that the code ref will be called during compilation to validate its type
rather than re-validating it with every accessor call.

=head1 INHERITANCE

When a class declares a prop which is also declared in the parent class, the
parent class' settings are overridden. Any options I<not> included in the
overriding class' prop declaration remain in effect in the child class.

  package A;

  use prop 'foo', rw => 1;
  use prop 'bar', req => 1, rw => 1;

  1;

  package B;

  use parent -norequire, 'A';

  use prop 'foo', req => 1; # B->foo is req, inherits rw
  use prop 'bar', rw => 0;  # B->bar inherits req, but is no longer rw

  1;

=head1 COMPILATION PHASES

=head2 BEGIN

C<use prop> statements are evaluated by the perl interpreter at the earliest
possible moment. At this time, C<prop> is still gathering prop declarations and
the class is not fully assembled.

=head2 CHECK

All props are assumed to be declared by the C<CHECK> phase. The first prop
declaration adds a C<CHECK> block to the package that installs all generated
accessor methods in the declaring class. This may additionally trigger any
parent classes (identified by C<@ISA>) which are not yet complete.

=head1 DEBUGGING

Adding C<use prop -debug> to your class will cause C<prop> to print the
generated constructor and accessor code just before it is evaluated.

=head1 PERFORMANCE

C<prop> is designed to be fast and have a low overhead. When available,
L<Class::XSAccessor> is used to generate the class accessors. This applies to
props that are not writable or are writable but have no declared type.

This behavior can be disabled by setting C<$slot::XS> to a negative value,
although this must be done in a C<BEGIN> block before declaring any slots, or
by setting the environmental variable C<SLOT_NO_XS> to a positive value before
running.

A minimal benchmark on my admittedly underpowered system compares L<Moose>,
L<Moo>, and L<prop>. The test includes multiple setters using a mix of
inherited, typed and untyped, attributes, which ammortizes the benefit of
Class::XSAccessor to L<Moo> and L<prop>.

  |           Rate   moo moose  prop
  | moo   355872/s    --  -51%  -63%
  | moose 719424/s  102%    --  -25%
  | prop  961538/s  170%   34%    --

Oddly, L<Moo> seemed to perform better running the same test without
L<Class::XSAccessor> installed.

  |           Rate   moo moose  prop
  | moo   377358/s    --  -50%  -56%
  | moose 757576/s  101%    --  -12%
  | prop  862069/s  128%   14%    --

=head1 AUTHOR

Jeff Ober <sysread@fastmail.fm>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by Jeff Ober.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
