#!perl

use Test::More tests => 3;

use strict;
use warnings;

use TryCatch;

sub content {
  try {
    return "pass";
  } catch ($e) {
    return "'an error occurred'";
  }
  return "fail";
}

is (main::content(), "pass",        "function");
is (main->content(), "pass",        "class method");
is ((bless {})->content(), "pass", "instance method");
