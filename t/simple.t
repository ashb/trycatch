use strict;
use warnings;
use Test::More tests => 6;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };

use FindBin qw/$Bin/;

use lib "$Bin/lib";

sub simple_return {
  try {
    return "simple_return";
    return "i wont get here";
  }

  die("return didn't unwind");
  return "bar";
}

sub simple_no_return {
  try {
    "simple_return"; # Not a return op
  }

  return "bar";
}

sub use_test {
  try {
    use TryCatchTest;
    return TryCatchTest::foo();
  }

}

is(simple_return(), "simple_return", "try with explicit return");
is(simple_no_return(), "bar", "try without explicity return");
is(use_test(), 42, "use in try block");

my $ran_catch = 0;

try {
    foo();
}
catch ($e) {
  $ran_catch = 1;
}
is($ran_catch, 0, "Catch block not run");

sub foo {
    return 1;
}


