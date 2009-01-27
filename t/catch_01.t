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

=for comment
sub simple_catch_type {
  try {
    die [1,2,3];
  }
  catch (ArrayRef[Int] $array) {
    return "Got an array of @$array";
  }
  catch ($e) {
    return "Got otherwise";
  }
}
=cut

is(simple_no_die(), "simple_return", "simple_return");
is(simple_die(), "We got a long Str error of 'Some str'");

