use strict;
use warnings;
use Test::More tests => 4;

$TryCatch::SPECIAL_VALUE = \"foo";
sub try {}
sub catch (&$) {
  my ($cond, $err) = @_;

  local *_ = \$err;
  return $cond->($err);
}

use Scalar::Util qw/blessed/;

sub simple_return {
  # try {
  #   return "simple_return";
  #   die "Foo";
  # }

  # This doesn't work with wantarray
  try my $__t_c_ret = eval {
    return "simple_return";
    die "Foo";
    return $TryCatch::SPECIAL_VALUE;
  };

  if (my $__t_c_error = $@) {
    die $__t_c_error;
  }
  if (!ref($__t_c_ret) || $__t_c_ret != $TryCatch::SPECIAL_VALUE) {
    return $__t_c_ret;
  }
}

sub simple_catch {
  # try {
  #   die "Foo";
  # }
  # catch (Str $e) {
  #   return "str_error: $e";
  # }

  try my $__t_c_ret = eval {
    die "Foo\n";
    return $TryCatch::SPECIAL_VALUE;
  };

  if (my $__t_c_error = $@) {
    if ( !ref($__t_c_error)) {
      my $e = $__t_c_error;
      return "str_error: $e";
    }
    die $__t_c_error;
  }
  if (!ref($__t_c_ret) || $__t_c_ret != $TryCatch::SPECIAL_VALUE) {
    return $__t_c_ret;
  }
}

sub simple_catch_cond {
  # try {
  #   if ($_[0]) {
  #     Foo::Error->throw;
  #   } else {
  #     die "Foo\n";
  #   }
  # }
  # catch (Str $e) {
  #   return "str_error: $e";
  # }
  # catch (Foo::Error $err) {
  #   return "Foo::Error\n"
  # }

  my $__t_c_ret = eval {
    if ($_[0]) {
      Foo::Error->throw;
    } else {
      die "Foo\n";
    }
    return $TryCatch::SPECIAL_VALUE;
  };

  if (my $__t_c_error = $@) {
    if (catch { !ref } $@) {
      my $e = $__t_c_error;
      return "str_error: $e";
    }
    if (catch { blessed($_) && $_->isa('Foo::Error') } $@) {
      my $err = shift;
      return "Foo::Error\n";
      return $TryCatch::SPECIAL_VALUE;
    }
    else {
      die $__t_c_error;
    }
  }
  if (!ref($__t_c_ret) || $__t_c_ret != $TryCatch::SPECIAL_VALUE) {
    return $__t_c_ret;
  }
}

is(simple_return(), "simple_return");
is(simple_catch(), "str_error: Foo\n");
is(simple_catch_cond(0), "str_error: Foo\n");
is(simple_catch_cond(1), "Foo::Error\n");

package #
  Foo::Error;

sub throw {
  die bless {}, __PACKAGE__;
}
