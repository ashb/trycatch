use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };

sub simple_return {
  try {
    return "simple_return";
  }

  die("foo\n");
  return "bar";
}

#sub simple_no_return {
#  try {
#    "simple_return"; # Not a return op
#  }
#
#  return "bar";
#}

#is(simple_return(), "simple_return");
simple_return();
#is(simple_no_return(), "bar");

