use strict;
use warnings;

require 5.008001;

use inc::Module::Install 0.77;

name 'TryCatch';
all_from 'lib/TryCatch.pm';

configure_requires 'ExtUtils::Depends';

requires 'Parse::Method::Signatures';
requires 'B::Hooks::EndOfScope' => 0.05;
requires 'B::Hooks::OP::Check' => 0.15;
requires 'B::Hooks::OP::PPAddr' => 0.02;
requires 'Devel::Declare';
requires 'Moose';
requires 'MooseX::Types::Moose';
requires 'Scope::Upper' => 0.06;

resources repository => 'http://github.com/ashb/trycatch/tree/master';

can_use('ExtUtils::Depends') or do {
  requires 'ExtUtils::Depends';
  WriteAll;
  exit 1;
};


my $pkg = ExtUtils::Depends->new('TryCatch', 'B::Hooks::OP::PPAddr', 'B::Hooks::OP::Check');
makemaker_args(
    $pkg->get_makefile_vars,
    #dist => { PREOP => 'pod2text lib/B/Hooks/OP/PPAddr.pm > $(DISTVNAME)/README' },
);

WriteAll;


