package SlotMakeMaker;

use strict;
use warnings;
use ExtUtils::MakeMaker;

my $name  = 'slot';
my $clean = 'slot';

sub MY::postamble {
  return <<EOS;

misc : readme manifest

release : test dist
\tcpan-upload \$(DISTVNAME).tar.gz  

EOS
}

WriteMakefile(
  NAME             => $name,
  VERSION_FROM     => "lib/$name.pm",
  ABSTRACT_FROM    => 'README.pod',
  LICENSE          => 'perl_5',
  MIN_PERL_VERSION => '5.008',
  PREREQ_PRINT     => 1,

  META_MERGE => {
   resources => {
      homepage => "https://github.com/sysread/$clean",

      bugtracker => {
         web => "https://github.com/sysread/$clean/issues"
      },

      repository => {
         type => "git",
         url  => "https://github.com/sysread/$clean.git",
         web  => "https://github.com/sysread/$clean"
      }
   },
  },

  MAN3PODS => {
    'README.pod' => "blib/man3/$name.3",
  },

  test => {
    TESTS => 't/*',
  },

  clean => {
    FILES => "*.bak $clean-*.tar.gz",
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
