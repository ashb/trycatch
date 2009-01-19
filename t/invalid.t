use strict;
use warnings;

use Test::More tests => 3;
use Test::Exception;

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };

eval <<'EOC';
  use TryCatch;

  sub foo { }
  try \&foo

EOC

like $@, 
     qr!^block required after try at \(eval \d+\) line \d+!,
     "no block after try with line number";
 
undef $@;
eval <<'EOC';
  use TryCatch;

  try { }
  catch 

EOC

like $@, 
     qr!block required after catch at \(eval \d+\) line \d+!,
     "block after catch with line number";

undef $@;
eval <<'EOC';
  use TryCatch;

  try { }
  catch (^Err $e) {}

EOC

like $@, 
     qr!block required after try at \(eval \d+\) line \d+!,
     "block after try with line number";
