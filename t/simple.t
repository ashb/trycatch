use strict;
use warnings;
use Test::More qw(no_plan);

BEGIN { use_ok "TryCatch", 'try'; }


sub foo {
  try {
      return "from foo";
  }

  my $foo = 'bar';
}

print foo();
