package TryCatch;

use strict;
use warnings;


use Devel::Declare ();
use B::Hooks::EndOfScope;
use B::Hooks::OP::PPAddr;
use Devel::Declare::Context::Simple;
use Parse::Method::Signatures;
use Moose::Util::TypeConstraints;
use Scope::Upper qw/unwind want_at :words/;
use TryCatch::Exception;
use Carp qw/croak/;

use base qw/DynaLoader Devel::Declare::Context::Simple/;


our $VERSION = '1.000003';
our $PARSE_CATCH_NEXT = 0;
our ($CHECK_OP_HOOK, $CHECK_OP_DEPTH) = (undef, 0);

sub dl_load_flags { 0x01 }

__PACKAGE__->bootstrap($VERSION);

use namespace::clean;

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

  my $ctx = TryCatch->new->init(@_);

  $ctx->skip_declarator;
  $ctx->skipspace;

  my $linestr = $ctx->get_linestr;

  return if substr($linestr, $ctx->offset, 2) eq '=>';

  $ctx->inject_if_block(
    $ctx->scope_injector_call,
    q#( sub#
  ) or croak "block required after try";

  if (! $CHECK_OP_DEPTH++) {
    $CHECK_OP_HOOK = TryCatch::XS::install_return_op_check();
  }

  
}

sub inject_scope {
  on_scope_end { 
    block_postlude() 
  }
}

# Called after the block from try {} or catch {}
# Look ahead and determine what action to take based on wether or note we
# see a 'catch' token after the block
sub block_postlude {

  my $ctx = TryCatch->new->init(
    '', 
    Devel::Declare::get_linestr_offset()
  );

  my $offset = $ctx->skipspace;
  my $linestr = $ctx->get_linestr;

  my $toke = '';
  my $len = 0;

  if ($len = Devel::Declare::toke_scan_word($offset, 1 )) {
    $toke = substr( $linestr, $offset, $len );
    $ctx->{Declarator} = $toke;
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
    substr($linestr, $offset, 0) = ')->run(@_);';
    $ctx->set_linestr($linestr);
  }
}


# turn 'catch() {' into '->catch({ TC_check_code;'
# the '->' is added by one of the postlude hooks
sub _parse_catch {
  my $pack = shift;
  my $ctx = TryCatch->new->init(@_);

  # Only parse catch when we've been told to (set in block_postlude)
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
  croak "Internal Error: _parse_catch expects to find '->catch' in linestr, found: "  
    . substr($linestr, $ctx->offset, $len)
    unless $sub eq '->catch';

  $ctx->inc_offset($len);
  $ctx->skipspace;

  my $var_code = "";
  my @conditions;
  # optional ()
  if (substr($linestr, $ctx->offset, 1) eq '(') {
    my $proto = $ctx->strip_proto;
    croak "Run-away catch signature"
      unless (length $proto);
    
    my $sig = Parse::Method::Signatures->new(
      input => $proto,
      from_namespace => $pack,
    );
    my $errctx = $sig->ppi;
    my $param = $sig->param;

    $sig->error( $errctx, "Parameter expected")
      unless $param;

    my $left = $sig->remaining_input;

    croak "TryCatch can't handle un-named vars in catch signature" 
      unless $param->can('variable_name');

    my $name = $param->variable_name;
    $var_code .= "my $name = \$@;";

    # (TC $var)
    if ($param->has_type_constraints) {
      my $tc = $param->meta_type_constraint;
      $TC_LIBRARY->{"$tc"} = $tc;
      push @conditions, "'$tc'";
    }

    # ($var where { $_ } )
    if ($param->has_constraints) {
      foreach my $con (@{$param->constraints}) {
        push @conditions, "sub $con";
      }
    }

  }
  push @conditions, "sub ";

  $ctx->inject_if_block(
    $ctx->scope_injector_call . $var_code,
    '(' . join(', ', @conditions)
  ) or croak "block required after catch";


  if (! $CHECK_OP_DEPTH++) {
    $CHECK_OP_HOOK = TryCatch::XS::install_return_op_check();
  }
}


1;

__END__

=head1 NAME

TryCatch - first class try catch semantics for Perl, without source filters.

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

As shown in the above example, complex Moose types can be used, including
L<MooseX::Types> style of type constraints

In addition to type checking via Moose type constraints, you can also use where
clauses to only match a certain sub-condition on an error. For example,
assuming that C<HTTPError> is a suitably defined TC:

 catch (HTTPError $e where { $_->code >= 400 && $_->code <= 499 } ) { 
   return "4XX error";
 }
 catch (HTTPError $e) {
   return "other http code";
 }

would return "4XX error" in the case of a 404 error, and "other http code" in
the case of a 302.

In the case where multiple catch blocks are present, the first one that matches
the type constraints (if any) will executed.

=head1 BENEFITS

B<return>. You can put a return in a try block, and it would do the right thing
- namely return a value from the subroutine you are in, instead of just from
the eval block. 

B<Type Checking>. This is nothing you couldn't do manually yourself, it does it
for you using Moose type constraints.

=head1 TODO

=over

=item *

Decide on C<finally> semantics w.r.t return values.

=item *

Write some more documentation

=back

=head1 KNOWN BUGS

Currently C<@_> is not accessible inside try or catch blocks, so assign this to
a lexical variable outside if you wish to access function arguments. i.e.: 

 sub foo {
   try { return $_[0] };
 }

will not work, instead you must do something similar to this:

 sub foo {
   my ($foo) = @_;
   try { return $foo }
 }

=head1 SEE ALSO

L<MooseX::Types>, L<Moose::Util::TypeConstraints>, L<Parse::Method::Signatures>.

=head1 AUTHOR

Ash Berlin <ash@cpan.org>

=head1 THANKS

Thanks to Matt S Trout and Florian Ragwitz for work on L<Devel::Declare> and
various B::Hooks modules

Vincent Pit for L<Scope::Upper> that makes the return from block possible.

=head1 LICENSE

Licensed under the same terms as Perl itself.

