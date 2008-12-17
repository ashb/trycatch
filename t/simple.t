use strict;
use warnings;
use Test::More tests => 4;

BEGIN { use_ok "TryCatch" }

sub foo {
  try {
      return "from foo";
  };
  
  die "shouldn't get here";
  my $foo = 'bar';
}


sub dies {
  try {
      die "shouldn't get here";
      return "from foo";
  };
  
  my $foo = 'bar';
}


is('from foo', foo());
is('bar', dies());
