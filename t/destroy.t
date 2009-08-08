use strict;
use warnings;

use Test::More;
use TryCatch;

{
  package ROBOT;
  sub DESTROY {
    # Something that does it 'wrong' and stomps on $@
    eval {};
  }
}

sub test {
  my ($create_object) = @_;
  try {
    try {
      my $obj;

      $obj = bless {}, "ROBOT" if ($create_object);
      eval {
        die "IN EVAL";
      };
        local $SIG{__DIE__} = sub { print "old die handler\n"};

      die "ERROR";
    }
    catch ($e) {
      print "caught error '$e'\n";
      return;
    }
  }
  catch ($e) {
    return $e;
  }
  print "caught nothing\n";
}

test();
test(1);

local $TODO = "work out what this needs to test";
fail;

done_testing;
