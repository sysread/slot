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
