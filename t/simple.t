use strict;
use warnings;
use Test::More tests => 2;

BEGIN { use_ok "TryCatch" }

sub simple_return {
  #try {
  #  1+1;
  #}
  try {
    return "simple_return";
  }

  return "bar";
}

is(simple_return(), "simple_return");
