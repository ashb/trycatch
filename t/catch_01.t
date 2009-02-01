use strict;
use warnings;
use Test::More tests => 7;

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

sub simple_catch_type {
  my @args = @_;
  try {
    die $args[0];
  }
  catch (ArrayRef[Int] $array) {
    return "Got an array of @$array";
  }
  catch ($e) {
    return "Got otherwise";
  }
}

sub catch_args {
  try {
    die $_[0];
  }
  catch (ArrayRef[Int] $array) {
    return "Got an array of @$array";
  }
  catch ($e) {
    return "Got otherwise";
  }
}

is(simple_no_die(), "simple_return", "simple_return");
is(simple_die(), "We got a long Str error of 'Some str'", "simple_die");

is(simple_catch_type([1,2,3]), "Got an array of 1 2 3", "simple_catch_type");
is(simple_catch_type(''), "Got otherwise", "simple_catch_type");

{
local $TODO = 'sort out @_ bug';
is(catch_args([1,2,3]), "Got an array of 1 2 3", "simple_catch_type");
is(catch_args(''), "Got otherwise", "simple_catch_type");
}

