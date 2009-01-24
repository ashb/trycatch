use strict;
use warnings;
use Test::More tests => 4;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };

use FindBin qw/$Bin/;

use lib "$Bin/lib";

sub simple_return {
  try {
    return "simple_return";
    return "i wont get here";
  }

  die("foo\n");
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

