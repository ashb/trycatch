use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };
#use TryCatch;

eval <<'EOC';
  use TryCatch;

  sub foo { }
  try \&foo

EOC

like $@, 
     qr!^block required after try at \(eval \d+\) line \d+$!,
     "no block after try";
#warn "q{$@}";

undef $@;
eval <<'EOC';
  use TryCatch;

  try { 1; }
  catch 

EOC

like $@, 
     qr!^block required after catch at \(eval \d+\) line \d+$!,
     "no block after catch";
#warn "q{$@}";

undef $@;
eval <<'EOC';
  use TryCatch;

  try { }
  catch (^Err $e) {}

EOC

like $@, 
     qr!^Error parsing signature at '.{1,10}' at \(eval \d+\) line \d+$!,
     "invalid catch signature";
#warn "q{$@}";

undef $@;
eval <<'EOC';
  use TryCatch;

  try { }
  catch ( {}

EOC

TODO: { 
local $TODO = "Make this error better";
like $@, 
     qr!^'\)' required after catch signature at \(eval \d+\) line \d+!,
     "invalid catch signature (missing parenthesis)";
}
