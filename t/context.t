use strict;
use warnings;

use Test::More;
use TryCatch;

my $last_context;
sub fun {
  my ($should_die) = @_;
  try {
    die 1 if $should_die;

    $last_context = wantarray;
  }
  catch ($e where { /^1/ }) {
    $last_context = wantarray;
  }
}

my @v;
$v[0] = fun();
is($last_context, '', "Scalar try context preserved");

@v = fun();
is($last_context, 1, "Array try context preserved");

fun();
is($last_context, undef, "void try context preserved");

$v[0] = fun(1);
is($last_context, '', "Scalar catch context preserved");

@v = fun(1);
is($last_context, 1, "Array catch context preserved");

fun(1);
is($last_context, undef, "void catch context preserved");

done_testing;
