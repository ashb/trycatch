use strict;
use warnings;
use Test::More tests => 7;
use Scope::Upper qw/unwind :words/;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };
#use TryCatch;

=for cut

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

=cut


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
    warn SUB(); 
    return "Got otherwise";
  }
  fail("didn't unwind or catch");
}
is(simple_catch_type([1,2,3]), "Got an array of 1 2 3", "simple_catch_type");
is(simple_catch_type(''), "Got otherwise", "simple_catch_type");


=for comment
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


{
local $TODO = 'sort out @_ bug';
is(catch_args([1,2,3]), "Got an array of 1 2 3", "simple_catch_type");
}
is(catch_args(''), "Got otherwise", "simple_catch_type");

=cut
