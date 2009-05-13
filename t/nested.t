use strict;
use warnings;
use Test::More tests => 4;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };

sub nested_1 {
  try {
    try {
      return "from nested_1";
    }
    catch ($e) {
    }
  }
}

sub nested_2 {
  try {
    nested_1();
    return "from nested_2";
  }
}

is( nested_1(), "from nested_1", "nested try");
is( nested_2(), "from nested_2", "call nested try");

my $val;
try {
    try { die "Foo" }
    catch ($e) { die "$e\n" }
}
catch ($e) {
    $val = "$e\n";
} 
like($val, qr/^Foo at line /, "Double nested try-catch behaves");
