use strict;
use warnings;
use Test::More;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };

use FindBin qw/$Bin/;

use lib "$Bin/lib";

sub simple_return {
  try {
    return "simple_return";
    return "i wont get here";
  } #bar

  die("return didn't unwind");
  return "bar";
}

is(simple_return(), "simple_return", "try with explicit return");

sub simple_no_return {
  try {
    my $val = "simple_return"; # Not a return op
  }

  return "bar";
}
is(simple_no_return(), "bar", "try without explicity return");


sub use_test {
  try {
    use TryCatchTest;
    return TryCatchTest::foo();
  }

}

is(use_test(), 42, "use in try block");

my $ran_catch = 0;
my $warnings = '';
$SIG{__WARN__} = sub { $warnings .= join('', @_) };

try {
    foo();
} #end of try
catch ($e) {
  $ran_catch = 1;
}

is($ran_catch, 0, "Catch block not run");
is($warnings, '', "No warnings from try in not in sub");

=for comment
=cut

sub foo {
    return 1;
}

done_testing;
