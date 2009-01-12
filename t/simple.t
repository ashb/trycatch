use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok "TryCatch" }

sub simple_return {
  try {
    return "simple_return";
  }

  print("foo\n");
  return "bar";
}
sub simple_no_return {
  try {
    "simple_return"; # Not a return op
  }

  return "bar";
}

is(simple_return(), "simple_return");
is(simple_no_return(), "bar");

__END__

sub simple_catch {
  try {
    die "Foo\n";
    return "Shouldn't get here";
  }
  catch (Str $e) {
    return "str_error: $e";
  }

  return "Shouldn't get here either";
}

sub catch_2 {
  try {
    die "Foo\n";
    return "Shouldn't get here";
  }
  catch (Foobar $err) {
    return "dont want this";
  }
  catch (Str $err) {
    return "str_error: $err";
  }

  return "Shouldn't get here either";
}

is(simple_catch(), "str_error: Foo\n");
