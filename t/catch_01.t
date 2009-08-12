use strict;
use warnings;
use Test::More;
use Test::Exception;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };

sub simple_no_die {
  try {
    return "simple_return";
       } # foo
  catch($e) {
    die "Shouldn't get here: $e";
  }

  diag("foo\n");
  return "bar";
}

is(simple_no_die(), "simple_return", "simple_return");

sub simple_die {
  my $msg = "no error";
  try {
    die "Some str\n";
  }
  catch (Str $err where { length $_ < 5 }) {
    chomp($err);
    $msg = "We got a short Str error of '$err'";
  }
  catch (Str $err where { length $_ >= 5 }) {
    chomp($err);
    $msg = "We got a long Str error of '$err'";
  }

  return $msg;
}
is(simple_die(), "We got a long Str error of 'Some str'", "simple_die");


sub simple_catch_type {
  my @args = @_;
  try {
    die $args[0];
  }
  catch (ArrayRef[Int] $array) {
    return "Got an array of @$array";
    fail("didn't unwind");
  }
  catch ($e) {
    return "Got otherwise";
  }
  fail("didn't unwind or catch");
}
is(simple_catch_type([1,2,3]), "Got an array of 1 2 3", "simple_catch_type");
is(simple_catch_type(''), "Got otherwise", "simple_catch_type");


sub catch_args {
  try {
    no warnings 'uninitialized';
    die $_[0];
  }
  catch (ArrayRef[Int] $array) {
    return "Got an array of @$array";
  }
  catch ($e) {
    return "Got otherwise";
  }
}


is(catch_args([1,2,3]), "Got an array of 1 2 3", "simple_catch_type");
is(catch_args(''), "Got otherwise", "simple_catch_type");


# Testing of how errors propogate when not caught
dies_ok {
  try {
    die { code => 500 };
  }
  catch ($e where {$_->{code} < 400} ) {
    pass("caught error")
  }
} "No catch-all causes error to propogate";


lives_ok {
  try {
    die { code => 500 };
  }
  catch ($e where {$_->{code} < 400} ) {
    fail("caught error when we shouldn't have")
  }
  catch {
    pass("Caught error in catch all");
  }
} "Catch-all doesn't cause error to propogate";


dies_ok {
  try {
    try {
      die { code => 500 };
    }
    catch { die }
  }
  catch ($e where {$_->{code} < 400} ) {
    fail("caught error when we shouldn't have")
  }
} "'die' propogates errors as expected";

done_testing();

