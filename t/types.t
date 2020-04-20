use strict;
use warnings;
use Test::More;

use FindBin qw/$Bin/;

use lib "$Bin/lib";
use TryCatch;

try {
  require NoType;
  pass("Types do not need to be pre-declared");
}
catch ($e) {
  fail("Types do not need to be pre-declared");
  diag($e);
}

try {
  require NoVarName;
  pass("Types can be declared without a var name");
}
catch ($e) {
  fail("Types can be declared without a var name");
  diag($e);
}

done_testing;

