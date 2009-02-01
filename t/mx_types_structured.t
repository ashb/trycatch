use strict;
use warnings;
use Test::More;

use Scope::Upper qw/unwind/;
BEGIN {
  eval { require MooseX::Types::Structured; };
  if ($@) {
    plan skip_all => "This test requires MooseX::Types::Structured"
  } else {
    plan tests => 3;
  }
}

BEGIN { use_ok "TryCatch" or BAIL_OUT("Cannot load TryCatch") };

use MooseX::Types::Structured qw/Dict/;

sub throw_struct {
  my @args = @_;
  try {
    die { code => $args[0] };
  }
  catch (Dict[code => Int] $err where { $_->{code} >= 200 } ) {
    return "Code over 200";
  }
  catch (Dict[code => Int] $err where { $_->{code} < 200 } ) {
    return "Code less than 200";
  }
  catch {
    return "otherwise";
  }
  return "no error";
}

is throw_struct(200), "Code over 200", "where condition 1";
is throw_struct(100), "Code less than 200", "where condition 2";
