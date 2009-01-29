use strict;
use warnings;
use Test::More tests => 2;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };

sub nested_1 {
  try {
    try {
      return "from nested_1";
    }
    catch ($e) {
    }
  }
}

is( nested_1(), "from nested_1", "nested return");
