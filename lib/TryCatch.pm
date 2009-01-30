package TryCatch;

use strict;
use warnings;

use base 'DynaLoader';

our $VERSION = '1.000000';
our $PARSE_CATCH_NEXT = 0;
our ($CHECK_OP_HOOK, $CHECK_OP_DEPTH) = (undef, 0);

sub dl_load_flags { 0x01 }

__PACKAGE__->bootstrap($VERSION);

use Sub::Exporter -setup => {
  exports => [qw/try/],
  groups => { default => [qw/try/] },
  installer => sub {
    my ($args, $to_export) = @_;
    my $pack = $args->{into};
    foreach my $name (@$to_export) {
      if (my $parser = __PACKAGE__->can("_parse_${name}")) {
        Devel::Declare->setup_for(
          $pack,
          { $name => { const => sub { $parser->($pack, @_) } } },
        );
      }
      if (my $code = __PACKAGE__->can("_extras_for_${name}")) {
        $code->($pack);
      }
    }
    Sub::Exporter::default_installer(@_);

  }
};

use Devel::Declare ();
use B::Hooks::EndOfScope;
use B::Hooks::OP::PPAddr;
use Devel::Declare::Context::Simple;
use Parse::Method::Signatures;
use Moose::Util::TypeConstraints;
use Scope::Upper qw/unwind want_at :words/;
use TryCatch::Exception;
use TryCatch::TypeParser;
use Carp qw/croak/;


# The actual try call itself. Nothing to do with parsing.
sub try {
  my ($sub) = @_;

  return new TryCatch::Exception( try => $sub, ctx => SUB(CALLER(1)) );

}

# Where we store all the TCs for catch blocks created at compile time
# Not sure we really want to do this, but we will for now.
our $TC_LIBRARY = {};

sub get_tc {
  my ($class, $tc) = @_;

  $TC_LIBRARY->{$tc} or die "Unable to find parse TC for '$tc'";
}

# From here on out its parsing methods.

sub _extras_for_try {
  my ($pack) = @_;

  Devel::Declare->setup_for(
    $pack,
    { catch => { const => sub { _parse_catch($pack, @_) } } }
  );
}

# Replace 'try {' with an 'try (sub {'
sub _parse_try {
  my $pack = shift;

  # Hide Devel::Declare from carp;
  local $Carp::Internal{'Devel::Declare'} = 1;

  my $ctx = Devel::Declare::Context::Simple->new->init(@_);

  if (my $len = Devel::Declare::toke_scan_ident( $ctx->offset )) {
    $ctx->inc_offset($len);
    $ctx->skipspace;

    my $linestr = $ctx->get_linestr;
    croak "block required after try"
      unless substr($linestr, $ctx->offset, 1) eq '{';

    substr($linestr, $ctx->offset+1,0) = q# BEGIN { TryCatch::try_postlude() }#;
    substr($linestr, $ctx->offset,0) = q#(sub #;
    $ctx->set_linestr($linestr);

    if (! $CHECK_OP_DEPTH++) {
      $CHECK_OP_HOOK = TryCatch::XS::install_return_op_check();
    }

  }
  
}

sub try_postlude {
  on_scope_end { block_postlude() }
}

sub catch_postlude {
  on_scope_end { block_postlude() }
}

sub close_block {
  on_scope_end { block_closer() }
}

# Called after the block from try {} or catch {}
sub block_postlude {

  my $ctx = Devel::Declare::Context::Simple->new->init(
    '', 
    Devel::Declare::get_linestr_offset()
  );

  my $offset = $ctx->skipspace;
  my $linestr = $ctx->get_linestr;

  my $toke = '';
  my $len = 0;

  if ($len = Devel::Declare::toke_scan_word($offset, 1 )) {
    $toke = substr( $linestr, $offset, $len );
  }

  if (--$CHECK_OP_DEPTH == 0) {
    TryCatch::XS::uninstall_return_op_check($CHECK_OP_HOOK);
  }
  if ($toke eq 'catch') {

    $ctx->skipspace;
    substr($linestr, $ctx->offset, 0) = ')->';
    $ctx->set_linestr($linestr);
    $TryCatch::PARSE_CATCH_NEXT = 1;
  } else {
    substr($linestr, $offset, 0) = ")->run;";
    $ctx->set_linestr($linestr);
  }
}

sub block_closer {
  my $offset = Devel::Declare::get_linestr_offset();
  my $linestr = Devel::Declare::get_linestr();
  substr($linestr,$offset, 0, "}");
  Devel::Declare::set_linestr($linestr);
}

# turn 'catch() {' into '->catch({ TC_check_code;'
# the '->' is added by one of the postlude hooks
sub _parse_catch {
  my $pack = shift;
  my $ctx = Devel::Declare::Context::Simple->new->init(@_);

  return unless $TryCatch::PARSE_CATCH_NEXT;
  $TryCatch::PARSE_CATCH_NEXT = 0;

  # Hide Devel::Declare from carp;
  local $Carp::Internal{'Devel::Declare'} = 1;
  local $Carp::Internal{'B::Hooks::EndOfScope'} = 1;
  local $Carp::Internal{'TryCatch'} = 1;

  $ctx->skipspace;
  my $linestr = $ctx->get_linestr;

  my $len = length "->catch";
  my $sub = substr($linestr, $ctx->offset, $len);
  die "_parse_catch expects to find '->catch' in linestr, found: "  
    . substr($linestr, $ctx->offset, $len)
    unless $sub eq '->catch';

  $ctx->inc_offset($len);
  $ctx->skipspace;

  my $var_code = "";
  my @conditions;
  # optional ()
  if (substr($linestr, $ctx->offset, 1) eq '(') {
    my $substr = substr($linestr, $ctx->offset+1);
    my ($param, $left) = Parse::Method::Signatures->param($substr);

    die "can't handle un-named vars yet" unless $param->can('variable_name');

    my $name = $param->variable_name;
    $var_code .= "my $name= \$@;";

    if ($param->has_type_constraints) {
      my $parser = TryCatch::TypeParser->new(package => $pack);
      my $tc = $parser->visit($param->type_constraints->data);
      $TC_LIBRARY->{"$tc"} = $tc;
      push @conditions, "'$tc'";
    }

    if ($param->has_constraints) {
      foreach my $con (@{$param->constraints}) {
        # This is far less than optimal;
        push @conditions, "sub $con";
      }
    }

    substr($linestr, $ctx->offset, length($linestr) - $ctx->offset - length($left), '');
    $ctx->set_linestr($linestr);
    $ctx->skipspace;
    if (substr($linestr, $ctx->offset, 1) ne ')') {
      croak "')' expected after catch signature";
    }

    substr($linestr, $ctx->offset, 1, '');
    $ctx->set_linestr($linestr);
    $ctx->skipspace;
  }

  croak "block required after catch"
    unless substr($linestr, $ctx->offset, 1) eq '{';

  substr($linestr, $ctx->offset+1,0) = 
    q# BEGIN { TryCatch::catch_postlude() }# . $var_code;
  push @conditions, "sub ";
  substr($linestr, $ctx->offset,0) = '(' . join(', ', @conditions);
  $ctx->set_linestr($linestr);

  if (! $CHECK_OP_DEPTH++) {
    $CHECK_OP_HOOK = TryCatch::XS::install_return_op_check();
  }
}


1;

__END__

=head1 NAME

TryCatch - first class try catch semantics for Perl, with no source filters.

=head1 SYNOPSIS

 use TryCatch;

 sub foo {
   try {
     # some code that might die
     return "return value from foo";
   }
   catch (Some::Class $e where { $_->code > 100 } ) {
   }
 }

=head1 SYNTAX

This module aims to give first class exception handling to perl via 'try' and
'catch' keywords. The basic syntax this module provides is C<try { # block }>
followed by zero or more catch blocks. Each catch block has an optional type
constraint on it the resembles Perl6's method signatures. 

Also worth noting is that the error variable (C<$@>) is localised to the
try/catch blocks and will not leak outside the scope, or stomp on a previous
value of C<$@>.

The simplest case of a catch block is just

 catch { ... }

where upon the error is available in the standard C<$@> variable and no type
checking is performed. The exception can instead be accessed via a named
lexical variable by providing a simple signature to the catch block as follows:

 catch ($err) { ... }

Type checking of the exception can be performed by specifing a type constraint
or where clauses in the signature as follows:

 catch (TypeFoo $e) { ... }
 catch (Dict[code => Int, message => Str] $err) { ... }

As shown in the above example, complex Mooose types can be used, including
L<MooseX::Types::Structured> if it is imported into the compilation unit.

In the case where multiple catch blocks are present, the first one that matches
the type constraints (if any) will executed.

=head1 TODO

=over

=item *

Decide on C<finally> semantics w.r.t return values.

=back

=head1 AUTHOR

Ash Berlin <ash@cpan.org>

=head1 THANKS

Thanks to Matt Trout and Florian Ragwitz for work on L<Devel::Declare> and
various B::Hooks modules

Vincent Pit for L<Scope::Upper> that makes the return from block possible.

=head1 LICENSE

Licensed under the same terms as Perl itself.

