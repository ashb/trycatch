package TryCatch;

use strict;
use warnings;


use Devel::Declare ();
use B::Hooks::EndOfScope;
use B::Hooks::OP::PPAddr;
use Devel::Declare::Context::Simple;
use Parse::Method::Signatures;
use Moose::Util::TypeConstraints;
use Scope::Upper qw/localize unwind want_at :words/;
use Carp qw/croak/;
use XSLoader;

use base qw/Devel::Declare::Context::Simple/;


our $VERSION = '1.001001_99';

# These are private state variables. Mess with them at your peril
our ($CHECK_OP_HOOK, $CHECK_OP_DEPTH) = (undef, 0);
our $NEXT_EVAL_IS_TRY;

# Stack of state for tacking nested. Each value is number of catch blocks at
# the current level. We are nested if @STATE > 1
our (@STATE);

XSLoader::load(__PACKAGE__, $VERSION);

use namespace::clean;

use Sub::Exporter -setup => {
  exports => [qw/try/],
  groups => { default => [qw/try/] },
  installer => sub {
    my ($args, $to_export) = @_;
    my $pack = $args->{into};
    my $ctx_class = $args->{parser} || 'TryCatch';

    TryCatch::XS::install_try_op_check();

    foreach my $name (@$to_export) {
      if (my $parser = __PACKAGE__->can("_parse_${name}")) {
        Devel::Declare->setup_for(
          $pack,
          { $name => { const => sub { $ctx_class->$parser($pack, @_) } } },
        );
      }
    }
    Sub::Exporter::default_installer(@_);

  }
};


# The actual try call itself. Nothing to do with parsing.
sub try () {
  return;
}

# Where we store all the TCs for catch blocks created at compile time
# Not sure we really want to do this, but we will for now.
our $TC_LIBRARY = {};

sub check_tc {
  my ($class, $tc) = @_;

  my $type = $TC_LIBRARY->{$tc} or die "Unable to find parse TC for '$tc'";

  return $type->check($TryCatch::Error);
}

# From here on out its parsing methods.

# Replace 'try {' with an 'try; { local $@; eval {'
sub _parse_try {
  my ($class,$pack, @args) = @_;

  # Hide Devel::Declare from carp;
  local $Carp::Internal{'Devel::Declare'} = 1;

  my $ctx = $class->new->init(@args);

  $ctx->skip_declarator;
  $ctx->skipspace;

  my $linestr = $ctx->get_linestr;

  # Let "try =>" be valid.
  return if substr($linestr, $ctx->offset, 2) eq '=>';

  # Shadow try to be a constant no-op sub
  $ctx->shadow(sub () { } );

  $ctx->inject_if_block(
    $ctx->injected_try_code . $ctx->scope_injector_call('{}'),
    q#;#
  ) or croak "block required after try";

  #$ctx->debug_linestr("try");
  if (! $TryCatch::CHECK_OP_DEPTH) {
    $TryCatch::CHECK_OP_DEPTH++;
    $TryCatch::CHECK_OP_HOOK = TryCatch::XS::install_return_op_check();
  }

  $ctx->debug_linestr('post try');

  # Number of catch blocks found, we only care about 0,1 and +1 cases tho
  $ctx->state_new_block();
  
}


sub injected_try_code {
  # try { ...
  # ->
  # try; { local $@; eval { ...

  return $_[0]->state_is_nested()
       ? 'local $TryCatch::CTX = Scope::Upper::HERE; eval {' # Nested case
       : 'local $@; eval {'
}

sub injected_after_try {
  # This semicolon is for the end of the eval
  return ';$TryCatch::Error = $@; } if ($TryCatch::Error) { ';
}

sub injected_no_catch_code {
  # This undef is to ensure that there is the eval{}; is called in void context
  # i.e that its not the last op in a subroutine
  return "};undef;";
}

sub injected_post_catch_code {
  # We do it like this so that PROPGATE gets called, in case anyone is using it
  return 'else { $@ = $TryCatch::Error; die } };undef;';
}


sub scope_injector_call {
  my $self = shift;
  my $inject = shift;
  return ' BEGIN { ' . ref($self) . "->inject_scope(${inject}) }; ";
}


sub inject_scope {
  my ($class, $opts) = @_;

  if ($opts->{hook}) {
    if (! $TryCatch::CHECK_OP_DEPTH) {
      $TryCatch::CHECK_OP_DEPTH++;
      $TryCatch::CHECK_OP_HOOK = TryCatch::XS::install_return_op_check();
    }
  }

  on_scope_end { 
    $class->block_postlude() 
  }
}

# Called after the block from try {} or catch {}
# Look ahead and determine what action to take based on wether or note we
# see a 'catch' token after the block
sub block_postlude {
  my ($class) = @_;
  my $ctx = $class->new->init(
    '', 
    Devel::Declare::get_linestr_offset()
  );

  my $offset = $ctx->skipspace;
  my $linestr = $ctx->get_linestr;

  my $toke = '';
  my $len = 0;

  # Since we're not being called from a normal D::D callback, we have to
  # find this info manually.
  if ($len = Devel::Declare::toke_scan_word($offset, 1 )) {
    $toke = substr( $linestr, $offset, $len );
    $ctx->{Declarator} = $toke;
  }

  if ($TryCatch::CHECK_OP_DEPTH && --$TryCatch::CHECK_OP_DEPTH == 0) {
    TryCatch::XS::uninstall_return_op_check($TryCatch::CHECK_OP_HOOK);
    $TryCatch::CHECK_OP_HOOK = '';
  }

  if ($toke eq 'catch') {
    # We don't want the 'catch' token in the output since it messes up the
    # if/else we build up. So dont let control go back to perl just yet.

    $ctx->_parse_catch;

  } else  {

    # No (more) catch blocks, so write the postlude
    my $code;
    if ($ctx->state_have_catch_block) {
      $code = $ctx->injected_post_catch_code;
    }
    else {
      $code = $ctx->injected_no_catch_code;
      $TryCatch::NEXT_EVAL_IS_TRY = 1;
    }

    substr($linestr, $offset, 0, $code);


    $ctx->set_linestr($linestr);
    $ctx->debug_linestr("finalizer");

    # This try/catch stmt is finished
    $ctx->state_end_block();
  }
}


# turn 'catch() {' into '->catch({ TC_check_code;'
# the '->' is added by one of the postlude hooks
sub _parse_catch {
  my ($ctx) = @_;

  # Hide Devel::Declare from carp;
  local $Carp::Internal{'Devel::Declare'} = 1;
  local $Carp::Internal{'B::Hooks::EndOfScope'} = 1;
  local $Carp::Internal{'TryCatch'} = 1;
  local $Carp::Internal{'TryCatch::Basic'} = 1;

  # This isn't a normal DD-callback, so we can strip_name to get rid of 'catch'
  my $offset = $ctx->offset;
  $ctx->strip_name;
  $ctx->skipspace;
 
  $ctx->debug_linestr('catch');
  my $linestr = $ctx->get_linestr;

  my ($code, $var_code, @conditions) = ("","");

  # optional ()
  if (substr($linestr, $ctx->offset, 1) eq '(') {
    ($var_code, @conditions) = $ctx->parse_proto()
  }

  @conditions = ('1') unless @conditions;

  unless ($ctx->state_have_catch_block()) {
    $TryCatch::NEXT_EVAL_IS_TRY = 1;
    $code = $ctx->injected_after_try
          . "if (";
  }
  else {
    $code = "elsif (";
  }

  $var_code = $ctx->scope_injector_call( 
    $ctx->state_is_nested() ? '{hook => 1}' : '{}'
  ) . $var_code;

  $ctx->inject_if_block(
    $var_code,
    $code . join(' && ', @conditions) . ')'
  ) or croak "block required after catch";

  $ctx->debug_linestr('post catch');

  $ctx->state_parsed_catch();
}

sub parse_proto {
  my ($self) = @_;

  my $proto = $self->strip_proto;
  croak "Run-away catch signature"
    unless (length $proto);

  return $self->parse_proto_using_pms($proto);
}

sub parse_proto_using_pms {
  my ($self, $proto) = @_;

  my @conditions;

  my $sig = Parse::Method::Signatures->new(
    input => $proto,
    from_namespace => $self->get_curstash_name,
  );
  my $errctx = $sig->ppi;
  my $param = $sig->param;

  $sig->error( $errctx, "Parameter expected")
    unless $param;

  my $left = $sig->remaining_input;

  my $var_code = '';

  if (my $var_name = $param->can('variable_name') ) {

    my $name = $param->$var_name();
    $var_code = "my $name = \$TryCatch::Error;";
  }

  # (TC $var)
  if ($param->has_type_constraints) {
    my $tc = $param->meta_type_constraint;
    $TryCatch::TC_LIBRARY->{"$tc"} = $tc;
    push @conditions, "TryCatch->check_tc('$tc')";
  }

  # ($var where { $_ } )
  if ($param->has_constraints) {
    foreach my $con (@{$param->constraints}) {
      $con =~ s/^{|}$//g;
      push @conditions, "do {local \$_ = \$TryCatch::Error; $con }";
    }
  }

  return $var_code, @conditions;
}

# Functions that wrap @STATE maniuplation into useful names
sub state_new_block {
  push @TryCatch::STATE, 0;
  return
}

sub state_end_block {
  pop @TryCatch::STATE;
  return;
}

sub state_is_nested {
  return @TryCatch::STATE > 1;
}

sub state_have_catch_block {
  return $TryCatch::STATE[-1] > 0;
}

sub state_parsed_catch {
  $TryCatch::STATE[-1]++;
}

*debug_linestr = !( ($ENV{TRYCATCH_DEBUG} || 0) & 1)
               ? sub {}
               : sub {
  my ($ctx, $message) = @_;

  local $Carp::Internal{'TryCatch'} = 1;
  local $Carp::Internal{'TryCatch::Basic'} = 1;
  local $Carp::Internal{'Devel::Declare'} = 1;
  local $Carp::Internal{'B::Hooks::EndOfScope'} = 1;
  local $Carp::Internal{'Devel::PartialDump'} = 1;
  Carp::cluck($message) if $message;

  require Devel::PartialDump;

  warn   "  Substr: ", Devel::PartialDump::dump(substr($ctx->get_linestr, $ctx->offset)),
       "\n  Whole:  ", Devel::PartialDump::dump($ctx->get_linestr), "\n\n";
};


1;

__END__

=head1 NAME

TryCatch - first class try catch semantics for Perl, without source filters.

=head1 DESCRIPTION

This module aims to provide a nicer syntax and method to catch errors in Perl,
similar to what is found in other languages (such as Java, Python or C++).  The
standard method of using C<< eval {}; if ($@) {} >> is often prone to subtle
bugs, primarily that its far too easy to stomp on the error in error handlers.
And also eval/if isn't the nicest idiom.

=head1 SYNOPSIS

 use TryCatch;

 sub foo {
   my ($self) = @_;

   try {
     die Some::Class->new(code => 404 ) if $self->not_found;
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

