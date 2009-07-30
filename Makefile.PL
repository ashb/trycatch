use strict;
use warnings;

use FindBin qw/$Bin/;

use inc::Module::Install 0.79;

perl_version '5.008001';
name 'TryCatch';
all_from 'lib/TryCatch.pm';


test_requires 'Test::More' => 0.88;
test_requires 'Test::Exception';

my %config_deps = (
  'ExtUtils::Depends' => 0.302,
);
# These are config and runtime deps
my %run_deps = (
  'B::Hooks::OP::Check' => 0.18,
  'B::Hooks::OP::PPAddr' => 0.03,
);

requires %run_deps;
requires 'Parse::Method::Signatures' => '1.003009';
requires 'B::Hooks::EndOfScope' => 0.08;
requires 'Devel::Declare' => '0.005007';
requires 'Moose';
requires 'MooseX::Types::Moose';
requires 'MooseX::Types';
requires 'Scope::Upper' => 0.06;
requires 'Variable::Magic' => 0.28;
requires 'Sub::Exporter' => 0.979;
requires 'XSLoader';

resources repository => 'http://github.com/ashb/trycatch/tree/master';

auto_provides;

configure_requires %config_deps, %run_deps;
my $ok = 1;

# Does the toolchain support configure_requires
# If yes, it should be here already.
can_use('ExtUtils::Depends') or do {
  warn "***\n* Your CPAN toolchain is out of date. Please upgrade it\n***\n"; sleep 5;
  requires %config_deps;
  
};

# Since we can bundle things under inc, do so. That way it should be easier to
# install
unshift @INC, "$Bin/inc/EUDeps";
can_use('ExtUtils::Depends') or do {
  warn "ExtUtils::Depends not installed and can't use version from inc!";
  $ok = 0;
};


unless ($ok) {
  WriteAll;
  exit 1;
}

my $pkg = ExtUtils::Depends->new('TryCatch', 'B::Hooks::OP::PPAddr', 'B::Hooks::OP::Check');
makemaker_args(
    $pkg->get_makefile_vars,
);

{ no warnings 'once';
if ($Module::Install::AUTHOR) {
  system('pod2text lib/TryCatch.pm > README');

  # Pull in the header files from B::Hooks modules we need.
  # This only works since I know they only use .h files, not XS or typemaps.

  #  Author only - use what ever modules we like!
  require Path::Class;
  require File::Copy::Recursive;

  Path::Class::dir(qw/inc EUDeps/)->rmtree;

  $File::Copy::Recursive::KeepMode = 0;
  my %deps = $pkg->get_deps;
  while (my ($mod, $conf) = each %deps ) {
    my $dest = Path::Class::dir('inc', 'EUDeps', split(/::/, $mod), 'Install', );
    my $src = Path::Class::dir($conf->{instpath});

    File::Copy::Recursive::dircopy("$src", "$dest");
  }
  File::Copy::Recursive::fcopy($INC{'ExtUtils/Depends.pm'}, 'inc/EUDeps/ExtUtils/');
}
}

WriteAll;


