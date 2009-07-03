use strict;
use warnings;
use Test::More tests => 6;

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

# same thing, but now we return from within the catch
sub nested_catch {
  try {      
      try {
        die "Some str\n";
      }
      catch ( $e ) {        
        return "caught in nested TC";
      }
  }
  
  return "didn't catch";
}

is( nested_catch(), "caught in nested TC", "nested catch" );

my $val;
try {
    try { die "Foo" }
    catch ($e) { die "$e" }
}
catch ($e) {
    $val = "$e";
} 
like($val, qr/^Foo at t[\/\\]nested.t line /, 
     "Nested try-catch in same function behaves");


# frif: uncatched exceptions should be rethrown
sub nested_rethrow {
  try {      
      try {
        die "Some str\n";
      }
      catch (Str $err where { length $_ < 5 }) {        
        return "caught in inner TC";
      }
  }
  catch {
    return "caught in outer TC";
  }
  
  return "didn't catch";
}

is( nested_rethrow(), "caught in outer TC", "nested rethrow" );
