use v5.10;
use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(
  class => 'My::Builder',
  code => q{
    sub ACTION_docs {
      use Pod::Readme;
      use Pod::Select;

      my $self = shift;

      podselect({ -output => 'README.pod' },
        'lib/slot.pm');

      my $parser = Pod::Readme->new();
      $parser->parse_from_file('README.pod', 'README');

      return $self->SUPER::ACTION_docs;
    }
  }
);

my $builder = $class->new(
  module_name       => 'slot',
  license           => 'perl',
  dist_author       => q{Jeff Ober <sysread@fastmail.fm>},
  dist_version_from => 'lib/slot.pm',
  dist_abstract     => 'Fast, simple, compile-time class declaration',

  requires => {
    'parent' => 0,
    'Carp'   => 0,
  },

  configure_requires => {
    'Pod::Readme' => 0,
    'Pod::Select' => 0,
  },

  build_requires => {
    'Pod::Readme' => 0,
    'Pod::Select' => 0,
    'Test::More'  => 0,
  },

  add_to_cleanup     => [ 'slot-*' ],
  create_makefile_pl => 'traditional',
);

$builder->create_build_script();
