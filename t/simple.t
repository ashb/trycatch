use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok "TryCatch" }

sub simple_return {
  #try {
  #  1+1;
  #}
  try {
    return "simple_return";
  }

  print("foo\n");
  return "bar";
}


sub simple_catch {
  try {
    die "Foo\n";
    return "Shouldn't get here";
  }
  catch {
    return "str_error: $e";
  }

  return "Shouldn't get here either";
}

is(simple_return(), "simple_return");
is(simple_catch(), "str_error: Foo\n");
