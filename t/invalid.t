use strict;
use warnings;

use Test::More tests => 8;
use Test::Exception;
use TryCatch;

test_for_error(
  qr/^block required after try at .*? line 4$/, 
  "no block after try",
  <<'EOC' );
use TryCatch;

sub foo { }
try \&foo
EOC


test_for_error(
  qr/^block required after catch at \(eval \d+\) line 6$/,
  "no block after catch",
  <<'EOC');
use TryCatch;

try { 1 }
catch 
EOC


test_for_error(
   qr/^Parameter expected near '\^' in '\^Err \$e' at \(eval \d+\) line 4$/,
   "invalid catch signature",
  <<'EOC');
use TryCatch;

try { }
catch (^Err $e) {}
EOC


TODO: { 
local $TODO = "Make this error better";

test_for_error(
  qr!^'\)' required after catch signature at \(eval \d+\) line 4!,
  "invalid catch signature (missing parenthesis)",
  <<'EOC');
use TryCatch;

try { }
catch ( {}

EOC

}


test_for_error(
  qr/^Can't locate object method "bar" via package "catch" .*?at \(eval \d+\) line 3\b/,
  "bareword between try and catch",
  <<'EOC');
use TryCatch;

try { } bar
catch {}

EOC

test_for_error(
  qr/^Bareword "catch" not allowed while "strict subs" in use at \(eval \d+\) line 3\b/,
  "catch is not special", 
  <<'EOC');
use TryCatch;

catch;
EOC

compile_ok("try is not too reserved", <<'EOC');
use TryCatch;

try => 1;
EOC

compile_ok(
  "catch is not special", 
  <<'EOC');
use TryCatch;

catch => 3;
EOC

sub test_for_error {
  my ($re, $msg, $code) = @_;
  try {
    eval $code;
    die $@ if $@;
    fail($msg);
  }
  catch ($e) {
    like($e, $re, $msg);
  }
}

sub compile_ok {
  my ($msg, $code) = @_;
  try {
    eval $code;
    die $@ if $@;
    pass($msg);
  }
  catch ($e) {
    diag($e);
    fail($msg);
  }
}
