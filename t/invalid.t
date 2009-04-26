use strict;
use warnings;

use Test::More tests => 17;
use Test::Exception;
use TryCatch;

my $line;

test_for_error(
  qr/^block required after try at .*? line (\d+)\b/, 
  "no block after try",
  <<'EOC' );
use TryCatch;

sub foo { }
try \&foo
EOC

is($line, 4, "Error from line 4");

test_for_error(
  qr/^block required after catch at \(eval \d+\) line (\d+)\b/,
  "no block after catch",
  <<'EOC');
use TryCatch;

try { 1 }
catch 
my $foo = 2;
EOC

$TODO = "Devel::Declare line number issue";
is($line, 4, "Error from line 4");

test_for_error(
   qr/^Parameter expected near '\^' in '\^Err \$e' at \(eval \d+\) line (\d+)\b/,
   "invalid catch signature",
  <<'EOC');
# line 1
use TryCatch;

try { }
catch (^Err $e) {}
next;
EOC

is($line, 4, "Error from line 4");

test_for_error(
  qr/^Run-away catch signature at \(eval \d+\) line (\d+)/,
  "invalid catch signature (missing parenthesis)",
  <<'EOC');
use TryCatch;

try { }
catch ( 



{}

1;
EOC

is($line, 4, "Error from line 4");


test_for_error(
  qr/^Can't locate object method "bar" via package "catch" .*?at \(eval \d+\) line (\d+)\b/,
  "bareword between try and catch",
  <<'EOC');
use TryCatch;

try { } bar
catch {}

EOC
undef $TODO;
is($line, 3, "Error from line 3");

test_for_error(
  qr/^Bareword "catch" not allowed while "strict subs" in use at \(eval \d+\) line (\d+)\b/,
  "catch is not special", 
  <<'EOC');
use TryCatch;

catch;
EOC
is($line, 3, "Error from line 3");


test_for_error(
  qr/^'SomeRandomTC' could not be parsed to a type constraint .*? at \(eval \d+\) line (\d+)\b/,
  "Undefined TC",
  <<'EOC');
use TryCatch;

try { }
catch (SomeRandomTC $e) {}

EOC

{
local $TODO = "Devel::Declare line number issue";
is($line, 4, "Error from line 4");
}

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

local $TODO = 'Sort out POD';
compile_ok("POD doesn't interfer with things.", <<'EOC');
use TryCatch;

try {
}

=head1 POD

=cut
EOC

sub test_for_error {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  local $TODO;
  local $SIG{__WARN__} = sub {};
  my ($re, $msg, $code) = @_;
  try {
    eval $code;
    die $@ if $@;
    fail($msg);
  }
  catch ($e) {
    like($e, $re, $msg);
    ($line) = ($e =~ /$re/);
  }
}

sub compile_ok {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
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
