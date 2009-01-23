use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };
#use TryCatch;

sub simple_no_die {
  try {
    return "simple_return";
       } # foo
  catch {
    die "Shouldn't get here\n";
  }

  diag("foo\n");
  return "bar";
}


sub simple_die {
  try {
    die "Some str\n";
  }
  catch (Str $err) {
    chomp($err);
    return "We got a Str error of '$err'";
  }

  return "no error";
}

is(simple_no_die(), "simple_return", "simple_return");
is(simple_die(), "We got a Str error of 'Some str'");

