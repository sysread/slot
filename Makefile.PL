package SlotMakeMaker;

use strict;
use warnings;
use ExtUtils::MakeMaker;

sub MY::postamble {
  return <<EOS;

misc : readme manifest

EOS
}

WriteMakefile(
  NAME             => 'slot',
  VERSION_FROM     => 'lib/slot.pm',
  ABSTRACT_FROM    => 'README.pod',
  LICENSE          => 'perl_5',
  MIN_PERL_VERSION => '5.008',
  PREREQ_PRINT     => 1,

  MAN3PODS => {
    'README.pod' => 'blib/man3/slots.3',
  },

  test => {
    TESTS => 't/*',
  },

  clean => {
    FILES => "*.bak slot-*.tar.gz",
  },

  BUILD_REQUIRES => {
    'ExtUtils::MakeMaker' => '6.63_03',
  },

  TEST_REQUIRES => {
    'Type::Tiny' => 0,
    'Test::More' => 0,
  },

  PREREQ_PM => {
    'Carp' => 0,
  },
);

1;
